#!/usr/bin/env bash
# Runs INSIDE the LXC as root (01-create-lxc.sh calls it for you). Safe to re-run.
# Creates the 'jarvis' service user, installs Hermes Agent for it, pre-installs the
# Anthropic/Telegram/Teams extras, and installs the Microsoft Teams CLI.
#
# NOTE on `sudo -iu jarvis ...`: sudo -i backslash-escapes the command, which turns
# every newline into a line continuation. Keep every command passed through it on
# ONE line, or the lines get glued together (a multi-line script silently breaks).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Teams CLI version this kit was checked against (needs Node >= 22.12; see README).
TEAMS_CLI_VERSION="3.1.0"
J=/home/jarvis
HERMES="$J/.local/bin/hermes"

warn() { printf '\n!! WARNING: %s\n\n' "$*" >&2; }

apt-get update
apt-get -y full-upgrade
# git/curl are installer prereqs. libatomic1 is needed by Hermes' managed Node; without
# it Hermes tries `sudo` to install it, and the jarvis user has no sudo rights.
# No Debian nodejs/npm: the Teams CLI runs on Hermes' own Node (see README, step 5).
# libsecret-1-0: without it the Teams CLI keeps its login in memory only, so `teams login`
# doesn't carry over to the next `teams` command.
apt-get -y install git curl ca-certificates tar coreutils libatomic1 sudo locales tzdata \
  libsecret-1-0
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo "America/New_York" > /etc/timezone

id jarvis >/dev/null 2>&1 || useradd -m -s /bin/bash jarvis

# --- Hermes, installed as jarvis -------------------------------------------------
# --non-interactive skips the installer's setup/gateway prompts; --skip-computer-use skips
# the desktop driver (headless box). The installer adds ~/.local/bin to jarvis' PATH itself.
echo ">> Installing Hermes Agent for user jarvis..."
sudo -iu jarvis bash -c 'set -o pipefail; curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive --skip-computer-use'
[ -x "$HERMES" ] || { echo "Hermes install did not produce $HERMES"; exit 1; }

# Optional features Hermes would otherwise lazy-install on first use (the Anthropic SDK,
# Telegram, Teams). Doing it now surfaces any failure here instead of in the gateway log.
echo ">> Installing Hermes extras: anthropic, telegram, teams..."
sudo -iu jarvis "$HERMES" pm install --extra anthropic --extra telegram --extra teams </dev/null \
  || warn "extras install failed. The gateway will retry on first start; or re-run: $HERMES pm install --extra anthropic --extra telegram --extra teams"

# --- Persona + secrets -------------------------------------------------------------
install -o jarvis -g jarvis -m 644 /root/SOUL.md "$J/.hermes/SOUL.md"
# The installer already created ~/.hermes/.env from Hermes' .env.example (which has live
# defaults in it), so append the kit's block once instead of replacing the file.
ENV_FILE="$J/.hermes/.env"
MARKER="# --- Jarvis kit secrets (from env.template) ---"
touch "$ENV_FILE"
if ! grep -qxF "$MARKER" "$ENV_FILE"; then
  { echo; echo "$MARKER"; grep -vxF "$MARKER" /root/env.template; } >> "$ENV_FILE"
  echo ">> Appended the kit's secrets block to the end of $ENV_FILE"
else
  echo ">> $ENV_FILE already has the kit's secrets block; left it alone"
fi
chown jarvis:jarvis "$ENV_FILE"
chmod 600 "$ENV_FILE"

# --- Teams CLI (bot registration) on Hermes' managed Node --------------------------
# `with-hermes-node CMD...` runs CMD with Hermes' pinned Node/npm first on PATH. It asks
# Hermes each time, so it keeps working after `hermes update` replaces Node.
install -d -o jarvis -g jarvis "$J/.local/bin" "$J/.local/share"
cat > "$J/.local/bin/with-hermes-node" <<'EOF'
#!/usr/bin/env bash
# Run a command with Hermes' managed Node/npm first on PATH. Written by 02-bootstrap.sh.
set -euo pipefail
p="$("$HOME/.local/bin/hermes" pm env node npm 2>/dev/null \
  | sed -n 's/^[[:space:]]*"PATH":[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -z "$p" ]; then
  echo "with-hermes-node: Hermes' managed Node isn't installed. Run: hermes pm install node npm" >&2
  exit 1
fi
export PATH="$p:$PATH"
exec "$@"
EOF
cat > "$J/.local/bin/teams" <<'EOF'
#!/usr/bin/env bash
# Microsoft Teams CLI on Hermes' managed Node. Written by 02-bootstrap.sh.
exec "$HOME/.local/bin/with-hermes-node" "$HOME/.local/share/teams-cli/bin/teams" "$@"
EOF
chown jarvis:jarvis "$J/.local/bin/with-hermes-node" "$J/.local/bin/teams"
chmod 755 "$J/.local/bin/with-hermes-node" "$J/.local/bin/teams"

echo ">> Installing the Teams CLI $TEAMS_CLI_VERSION on Hermes' Node..."
if sudo -iu jarvis "$HERMES" pm install node npm </dev/null \
   && sudo -iu jarvis "$J/.local/bin/with-hermes-node" node -e 'const [a,b]=process.versions.node.split(".").map(Number); console.log("   Hermes Node is v"+process.versions.node); process.exit(a>22||(a===22&&b>=12)?0:1)' \
   && sudo -iu jarvis "$J/.local/bin/with-hermes-node" npm install -g --prefix "$J/.local/share/teams-cli" "@microsoft/teams.cli@$TEAMS_CLI_VERSION" </dev/null; then
  echo ">> Teams CLI: $(sudo -iu jarvis "$J/.local/bin/teams" --version)"
else
  warn "Teams CLI install failed (it needs Node >= 22.12). Terminal and Telegram are unaffected; fix this before README step 5."
fi

sudo -iu jarvis "$HERMES" doctor </dev/null || true
echo ">> Bootstrap done."
