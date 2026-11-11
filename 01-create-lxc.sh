#!/usr/bin/env bash
# Run on the R730 Proxmox HOST as root.
# Creates an unprivileged Debian 13 LXC for Hermes Agent ("Jarvis"),
# pushes 02-bootstrap.sh into it, and runs it.
set -euo pipefail

# ---- Edit these to match your host ----
CT_NAME="xen-jarvis"
STORAGE="local-zfs"        # rootfs storage (the R730 has local-zfs, no local-lvm)
TEMPLATE_STORAGE="local"   # where CT templates live
BRIDGE="vmbr0"             # home LAN bridge (NOT vmbr1 / VPN bridge)
IP_CFG="dhcp"              # or e.g. "192.168.128.180/24,gw=192.168.128.1"
CORES=4
MEMORY=4096                # MB
SWAP=1024
DISK=24                    # GB
VMID="${VMID:-$(pvesh get /cluster/nextid)}"
# ---------------------------------------

HERE="$(cd "$(dirname "$0")" && pwd)"

# Re-running this script must not create a second Jarvis CT.
EXISTING="$(pct list | awk -v n="$CT_NAME" 'NR>1 && $NF==n {print $1}')"
if [ -n "$EXISTING" ]; then
  echo "A CT named $CT_NAME already exists (VMID $EXISTING). To re-run only the bootstrap:"
  echo "  pct push $EXISTING $HERE/02-bootstrap.sh /root/02-bootstrap.sh --perms 755"
  echo "  pct exec $EXISTING -- /root/02-bootstrap.sh"
  exit 1
fi

# A static IP without gw= leaves the CT with LAN DNS but no internet ("Network is unreachable").
case "$IP_CFG" in
  dhcp|*gw=*) ;;
  *) echo "IP_CFG is a static address with no gateway. Add ,gw=<router IP> (this host's: $(ip route show default | awk '{print $3; exit}'))"
     exit 1 ;;
esac

echo ">> Locating latest Debian 13 template..."
pveam update >/dev/null
# pveam lists amd64 and arm64 builds; a plain version sort would pick arm64. Match the host.
ARCH="$(dpkg --print-architecture)"
TEMPLATE="$(pveam available --section system \
  | awk -v a="$ARCH" '$2 ~ "^debian-13-standard_.*_" a "\\.tar" {print $2}' | sort -V | tail -1)"
[ -n "$TEMPLATE" ] || { echo "No debian-13-standard template for $ARCH found"; exit 1; }
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi

echo ">> Creating CT $VMID ($CT_NAME) from $TEMPLATE"
pct create "$VMID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE" \
  --hostname "$CT_NAME" \
  --unprivileged 1 \
  --features nesting=1 \
  --cores "$CORES" --memory "$MEMORY" --swap "$SWAP" \
  --rootfs "$STORAGE:$DISK" \
  --net0 "name=eth0,bridge=$BRIDGE,ip=$IP_CFG" \
  --onboot 1 \
  --ostype debian

pct start "$VMID"
echo ">> Waiting for network..."
NET_OK=0
# Needs a default route AND DNS: DNS alone can work on the LAN with no gateway set.
for _ in $(seq 1 30); do
  if pct exec "$VMID" -- sh -c '{ ip route show default; ip -6 route show default; } | grep -q . && getent hosts deb.debian.org' >/dev/null 2>&1; then
    NET_OK=1; break
  fi
  sleep 2
done
if [ "$NET_OK" -ne 1 ]; then
  echo "CT $VMID has no default route or DNS after 60 s. Check BRIDGE/IP_CFG (gw=), then: pct exec $VMID -- ip route"
  exit 1
fi

pct push "$VMID" "$HERE/02-bootstrap.sh" /root/02-bootstrap.sh --perms 755
pct push "$VMID" "$HERE/SOUL.md"         /root/SOUL.md
pct push "$VMID" "$HERE/env.template"    /root/env.template
if ! pct exec "$VMID" -- /root/02-bootstrap.sh; then
  echo
  echo "!! Bootstrap failed inside CT $VMID (the CT itself is fine). Fix the cause, then re-run:"
  echo "   pct exec $VMID -- /root/02-bootstrap.sh"
  exit 1
fi

IP="$(pct exec "$VMID" -- hostname -I | awk '{print $1}')"
echo
echo "=================================================="
echo " CT $VMID ($CT_NAME) is up at $IP"
[ "$IP_CFG" = "dhcp" ] && echo " (DHCP: reserve $IP for this CT on your router; Caddy points at it.)"
echo " Next:  pct enter $VMID   then   su - jarvis"
echo " and follow README.md step 3."
echo "=================================================="
