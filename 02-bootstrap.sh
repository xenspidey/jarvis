#!/usr/bin/env bash
# Runs INSIDE the LXC as root (01-create-lxc.sh calls it for you).
# Creates the 'jarvis' service user and installs Hermes Agent for it.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y full-upgrade
# git/curl/tar/sha256 are installer prereqs; libatomic1 is needed by Hermes' managed Node.
# nodejs/npm are only for the Microsoft Teams CLI (bot registration).
apt-get -y install git curl ca-certificates tar coreutils libatomic1 sudo \
  nodejs npm locales tzdata
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

id jarvis >/dev/null 2>&1 || useradd -m -s /bin/bash jarvis

# Hermes install as the jarvis user (headless box: skip desktop computer-use driver)
sudo -iu jarvis bash -lc '
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive --skip-computer-use
  grep -q ".local/bin" ~/.bashrc || echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc
'

# Persona + secrets template
install -o jarvis -g jarvis -m 644 /root/SOUL.md /home/jarvis/.hermes/SOUL.md
if [ ! -f /home/jarvis/.hermes/.env ]; then
  install -o jarvis -g jarvis -m 600 /root/env.template /home/jarvis/.hermes/.env
else
  install -o jarvis -g jarvis -m 600 /root/env.template /home/jarvis/.hermes/env.template
  echo "NOTE: ~/.hermes/.env already existed; template saved alongside as env.template"
fi

# Teams CLI (global) for creating the bot registration
npm install -g @microsoft/teams.cli@preview

sudo -iu jarvis bash -lc 'export PATH="$HOME/.local/bin:$PATH"; hermes doctor || true'
echo ">> Bootstrap done."
