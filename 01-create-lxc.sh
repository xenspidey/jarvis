#!/usr/bin/env bash
# Run on the R730 Proxmox HOST as root.
# Creates an unprivileged Debian 13 LXC for Hermes Agent ("Jarvis"),
# pushes 02-bootstrap.sh into it, and runs it.
set -euo pipefail

# ---- Edit these to match your host ----
CT_NAME="xen-jarvis"
STORAGE="local-lvm"        # rootfs storage
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

echo ">> Locating latest Debian 13 template..."
pveam update >/dev/null
TEMPLATE="$(pveam available --section system | awk '/debian-13-standard/ {print $2}' | sort -V | tail -1)"
[ -n "$TEMPLATE" ] || { echo "No debian-13-standard template found"; exit 1; }
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
for _ in $(seq 1 30); do
  pct exec "$VMID" -- getent hosts deb.debian.org >/dev/null 2>&1 && break
  sleep 2
done

pct push "$VMID" "$HERE/02-bootstrap.sh" /root/02-bootstrap.sh --perms 755
pct push "$VMID" "$HERE/SOUL.md"         /root/SOUL.md
pct push "$VMID" "$HERE/env.template"    /root/env.template
pct exec "$VMID" -- /root/02-bootstrap.sh

IP="$(pct exec "$VMID" -- hostname -I | awk '{print $1}')"
echo
echo "=================================================="
echo " CT $VMID ($CT_NAME) is up at $IP"
echo " Next:  pct enter $VMID   then   su - jarvis"
echo " and follow README.md step 3."
echo "=================================================="
