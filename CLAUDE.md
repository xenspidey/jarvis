# Jarvis — project context for Claude Code

Brian's personal assistant: Nous Research **Hermes Agent**, using the persona "Jarvis", self-hosted on his Proxmox homelab.

## Environment
- Proxmox host: Dell R730 `R730`, 192.168.128.172. Debian 13 **unprivileged** LXCs are the house standard.
- Reverse proxy: Caddy in LXC `xen-pxy`, handles `*.xenspidey.com`.
- Other LXCs: `xen-nas` (101), `xen-vpn` (110, WireGuard; isolated bridge `vmbr1` 10.10.10.0/24). Don't touch them.
- Jarvis gets its own LXC `xen-jarvis` on `vmbr0` with **no** `/var/storage` mount, because Hermes has shell access.

## Decisions so far
- Model: Anthropic API key (`ANTHROPIC_API_KEY` in `~/.hermes/.env`), chosen with `hermes model`.
- Channels: terminal, Telegram (outbound polling), Microsoft Teams (bot at `https://jarvis.xenspidey.com/api/messages` → Caddy → LXC:3978).
- The gateway runs as a **system** service: `hermes gateway install --system --run-as-user jarvis`. Hermes refuses user services inside containers.
- Allowlists are always on (`TELEGRAM_ALLOWED_USERS`, `TEAMS_ALLOWED_USERS`). Never use `*_ALLOW_ALL_USERS`.
- Brian's rules for Jarvis and for you: don't guess (verify, or say "I don't know"); verify URLs; ask before destructive or irreversible actions.

## Phase 1 — basics (CURRENT)
Files in this folder: `01-create-lxc.sh` (run on the host), `02-bootstrap.sh` (runs in the CT), `SOUL.md`, `env.template`, `Caddyfile.snippet`, `README.md` (runbook).
Untested on real hardware. Open items to verify while running it:
- Does the installer accept `--non-interactive --skip-computer-use` via `bash -s --`?
- Is the Teams webhook on 3978 bound to 0.0.0.0 or only to 127.0.0.1? If only localhost, xen-pxy can't reach it. Find a bind option, or put a local proxy in the CT.
- Where the Teams extra goes: `python -c "import pm; pm.sync_venv(['teams'], explicit=True)"` needs Hermes' venv Python.
- Does Debian 13's `nodejs` meet the Teams CLI's version requirement?

## Phase 2 — planned, not started
- Hardware: 1–2 Tesla P40 (24 GB, Pascal sm_61) in the R730. Needs the GPU enablement kit, 1100 W PSUs, and the correct riser-to-GPU power cable (check orientation; the wrong cable has fried P40s). Driver branch 580 (the last for Pascal, LTS to mid-2028). Ollama via its CUDA 12 runner. vLLM does NOT support sm_61.
- Local model in Ollama: Hermes needs ≥64K context (Modelfile `num_ctx`). The docs name `gemma4:31b` as the reliable tool-calling option.
- Routing: Claude as the main model first; local model for delegation and background work; flip to local-first after evaluation. The `delegation.*` and `fallback_providers` keys are in config.yaml. Still to test: whether an unreachable host triggers fallback.
- Voice: Home Assistant LXC (≥ 2026.10) + Whisper/Piper on the P40s + EchoMuse firmware on Echo Dot 2nd gen / Echo 2nd gen + the Hermes Voice integration (majorminorlabs/hermes-voice, v0.1). Brian should confirm the Echo models before flashing.
- Family: voice goes to a restricted kid-safe Hermes profile; Brian's full profile only over Telegram/Teams with admin roles. Speaker ID (local add-on) is for personalization only, never for permissions.

## Docs
https://hermes-agent.nousresearch.com/docs/ (machine index: /docs/llms.txt)
