# Jarvis — project context for Claude Code

Brian's personal assistant: Nous Research **Hermes Agent**, using the persona "Jarvis", self-hosted on his Proxmox homelab.

## Environment
- Proxmox host: Dell R730 `R730`, 192.168.128.172. Debian 13 **unprivileged** LXCs are the house standard.
- Host facts (preflight 2026-11-11): PVE 9.2.26, amd64. Storage: `local` (dir, templates) and `local-zfs` (zfspool, CT disks); there is **no** `local-lvm`. Bridges: `vmbr0` only (no `vmbr1` listed, even though xen-vpn is documented on it). Next free VMID was 112. NFS storage `backup` was offline (not ours).
- Reverse proxy: Caddy in LXC `xen-pxy`, handles `*.xenspidey.com`.
- Other LXCs: `xen-nas` (101), `xen-vpn` (110, WireGuard; isolated bridge `vmbr1` 10.10.10.0/24). Don't touch them.
- Jarvis gets its own LXC `xen-jarvis` on `vmbr0` with **no** `/var/storage` mount, because Hermes has shell access.

## Decisions so far
- Model: Anthropic API key (`ANTHROPIC_API_KEY` in `~/.hermes/.env`), chosen with `hermes model`.
- Channels: terminal and Microsoft Teams (bot at `https://jarvis.xenspidey.com/api/messages` → Caddy → LXC:3978). **Telegram dropped** (2026-11-11, Brian's call; the blank TELEGRAM_* lines in .env are harmless). End goal is voice (Phase 2). Teams is now Brian's only remote admin channel besides the terminal.
- The gateway runs as a **system** service: `hermes gateway install --system --run-as-user jarvis`. Hermes refuses user services inside containers.
- Allowlists are always on (`TELEGRAM_ALLOWED_USERS`, `TEAMS_ALLOWED_USERS`). Never use `*_ALLOW_ALL_USERS`.
- Brian's rules for Jarvis and for you: don't guess (verify, or say "I don't know"); verify URLs; ask before destructive or irreversible actions.
- When walking Brian through host/CT steps: give ONE command, wait for its output, then the next. No branching "if X do this, else that" plans.

## Phase 1 — basics (CURRENT)
Files in this folder: `01-create-lxc.sh` (run on the host), `02-bootstrap.sh` (runs in the CT), `SOUL.md`, `env.template`, `Caddyfile.snippet`, `README.md` (runbook).
Being run on the R730 now (status at the end of this list). The open items were answered from the Hermes source at stable tag v0.23.1 (the installer's default channel) and the Teams CLI 3.1.0 package:
- Installer flags: `--non-interactive` and `--skip-computer-use` are both accepted (scripts/install.sh).
- Teams bind: the listener defaults to all interfaces, IPv4+IPv6 (`_DEFAULT_HOST = None`); `TEAMS_HOST` pins it. `/health` returns `ok`. xen-pxy can reach it, so no local proxy is needed.
- Teams extra: `hermes pm install --extra teams` (also `anthropic`, `telegram`; all are lazy-installed otherwise). The bootstrap runs it.
- Node: Teams CLI 3.x needs Node >= 22.12. Debian 13's `nodejs` version wasn't checked (packages.debian.org isn't reachable from the cloud session), so the kit doesn't use it. `~/.local/bin/teams` runs the CLI on Hermes' managed Node (v26.12.1 in v0.23.1) through `with-hermes-node`, which calls `hermes pm env node npm`.

Fixed in the kit:
- `sudo -i` turns newlines into line continuations, so the old two-line `bash -lc '...'` passed `grep ...` to install.sh ("unknown option"), Hermes never installed, and the `||` hid it. Commands sent through `sudo -iu` must stay on one line.
- The installer creates `~/.hermes/.env` itself, from `.env.example`, which has live defaults. The kit now appends its block once, guarded by a marker line.
- Teams CLI login is in-memory only without `libsecret-1-0` (now installed); with it, the CLI falls back to a plaintext `~/.config/teams-cli/msal-cache.json`. The runbook registers the bot before the gateway starts, then runs `teams logout` and deletes the cache. Login uses `--device-code` (headless CT).
- `01-create-lxc.sh` refuses to create a duplicate CT, fails clearly if the network doesn't come up, and prints the re-run command if the bootstrap fails.
- From the host preflight: `STORAGE` is now `local-zfs`, and the template pick matches the host arch, because `pveam` lists amd64 and arm64 and a plain sort took arm64.
- First real run (2026-11-11): CT 112 `xen-jarvis` was created with a static IP ending .112. The bootstrap failed at `apt-get update` with "Network is unreachable": no default route, most likely `IP_CFG` without `gw=`. DNS still resolved, so the old DNS-only wait passed. The script now rejects a static `IP_CFG` without `gw=` and waits for a default route.
- Fixed live with `pct set 112 --net0 ...,gw=192.168.128.1` (the host's gateway). The bootstrap re-run then succeeded with no warnings: Hermes installed, extras installed, Hermes Node v26.12.1, Teams CLI 3.1.0. CT 112 = 192.168.128.112 (Caddy's JARVIS_IP).
- `hermes model` → Anthropic, Fable. In v0.23.1 the `hermes` chat CLI goes through the gateway (`hermes gateway ensure`) and starts an unmanaged background gateway if none is running, so the system service is installed BEFORE first chat (README order needs updating to match).
- Root-run `hermes` under `pct exec` (no SUDO_USER) uses /root/.hermes as a borrowing data root and refuses (ownership guard). Working form: `pct exec 112 -- env HERMES_HOME=/home/jarvis/.hermes /home/jarvis/.local/bin/hermes gateway install --system --run-as-user jarvis --start-now --start-on-login`. That gave unit **`hermes-gateway-c51abf38`** (hashed name, because the home isn't root's native one); it is running as jarvis. A failed first attempt may have left `/root/.hermes` (harmless).
- Root-run hermes leaves root-owned `__pycache__/*.pyc` in the checkout; fixed with `find /home/jarvis ! -user jarvis -exec chown jarvis:jarvis {} +`. For lifecycle as root, prefer `systemctl … hermes-gateway-c51abf38` (no Python as root); `systemctl reload` = graceful drain.
- Install warned `/run/user/1000/bus did not appear`: fixed by `apt-get install dbus-user-session` + `systemctl restart user@1000.service` (now in the bootstrap).
- Terminal chat verified: replies as Jarvis ("Hello, Brian."), config.yaml `provider: "anthropic"`, `default: "claude-fable-5-2"`; the banner's "Nous Research" is branding. Only one gateway process (inside the service cgroup), so the CLI attached to the service. Shared metrics: off.
- Channel order decided 2026-11-11: **Hermes Desktop app first** (Windows, voice: dictation/live voice/wake word), then Discord (phone voice), then decide on Teams. Echo/Home Assistant stays Phase 2.
- Desktop connects with the **SSH** connection kind (`jarvis@192.168.128.112`): the app tunnels in and starts `hermes serve` itself on loopback, so no LAN port or auth provider. Set the connection's Hermes path to `/home/jarvis/.local/bin/hermes` (Debian's .bashrc returns early for non-interactive shells). Download per docs: https://hermes-agent.nousresearch.com/desktop (not fetchable from the cloud session). sshd in CT 112: active. Brian's PC key (`id_ed25519.pub`) is in jarvis' authorized_keys; `ssh jarvis@192.168.128.112` works without a password, and the host key matched the ED25519 fingerprint from CT creation (SHA256:pOXpGcBy…OcbU). His known_hosts had OLD keys for .112, so another device used that IP before; make sure it is retired.
- Desktop app connected (Primary gateway → Connect via SSH: host 192.168.128.112, user jarvis, identity `C:\Users\BrianCalendine\.ssh\id_ed25519`, Hermes path `/home/jarvis/.local/bin/hermes`). Test SSH: "Reachable … Hermes found"; chat replied "Morning, Brian."
- Voice plan (fully local, no keys): STT `local` (faster-whisper, extra `stt-whisper`, model `base` ~150 MB from huggingface.co on first use); TTS `piper` (extra `piper`, piper-tts 1.8.0, voice auto-downloaded to ~/.hermes/cache/piper-voices/; default `en_US-lessac-medium`). ffmpeg is a pm package (`hermes pm install ffmpeg`). Hermes' default TTS is `edge` (Microsoft cloud), so set `tts.provider piper` explicitly. Gateway-only providers relay audio through the gateway for the Desktop app.
- Voice install done: `hermes pm install ffmpeg && hermes pm install --extra stt-whisper --extra piper` (as jarvis), then `hermes config set tts.provider piper` / `stt.provider local`, then gateway restart. Gotcha: the Desktop app's SSH-started `hermes serve` (runs in an ssh session cgroup, not the service) kept the OLD dependency generation, so the error was "piper-tts package not installed". Fix: `kill <serve pid>` then Desktop → Save and reconnect. **After any `pm install`, restart BOTH the gateway service and the Desktop's serve.** Piper read-aloud verified working.

## Phase 2 — planned, not started
- Hardware: 1–2 Tesla P40 (24 GB, Pascal sm_61) in the R730. Needs the GPU enablement kit, 1100 W PSUs, and the correct riser-to-GPU power cable (check orientation; the wrong cable has fried P40s). Driver branch 580 (the last for Pascal, LTS to mid-2028). Ollama via its CUDA 12 runner. vLLM does NOT support sm_61.
- Local model in Ollama: Hermes needs ≥64K context (Modelfile `num_ctx`). The docs name `gemma4:31b` as the reliable tool-calling option.
- Routing: Claude as the main model first; local model for delegation and background work; flip to local-first after evaluation. The `delegation.*` and `fallback_providers` keys are in config.yaml. Still to test: whether an unreachable host triggers fallback.
- Voice: Home Assistant LXC (≥ 2026.10) + Whisper/Piper on the P40s + EchoMuse firmware on Echo Dot 2nd gen / Echo 2nd gen + the Hermes Voice integration (majorminorlabs/hermes-voice, v0.1). Brian should confirm the Echo models before flashing.
- Family: voice goes to a restricted kid-safe Hermes profile; Brian's full profile only over Telegram/Teams with admin roles. Speaker ID (local add-on) is for personalization only, never for permissions.

## Docs
https://hermes-agent.nousresearch.com/docs/ (machine index: /docs/llms.txt)
