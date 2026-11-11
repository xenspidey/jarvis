# Jarvis (Hermes Agent) on the R730

Unprivileged Debian 13 LXC, `jarvis` service user, Anthropic API, and three ways to talk to it: terminal, Telegram and Teams.

## 1. Copy the kit to the R730 host
```bash
scp -r jarvis/ root@192.168.128.172:/root/
```

## 2. Create the container (on the host)
Check the variables at the top of `01-create-lxc.sh` (storage, bridge, IP), then:
```bash
cd /root/jarvis && chmod +x *.sh && ./01-create-lxc.sh
```
This creates the CT, installs Hermes for user `jarvis`, drops in `SOUL.md` (the Jarvis persona) and a `.env` template, and installs the Teams CLI.

## 3. Model: Anthropic
```bash
pct enter <VMID>
su - jarvis
nano ~/.hermes/.env          # paste ANTHROPIC_API_KEY
hermes model                 # pick Anthropic and a Claude model
hermes                       # say hi; check that it introduces itself as Jarvis
hermes doctor
```
This is the terminal option. From now on, `ssh` → `pct enter` → `su - jarvis` → `hermes`.

## 4. Telegram
1. Telegram → @BotFather → `/newbot` (the username must end in `bot`). Copy the token.
2. Message @userinfobot to get your numeric ID.
3. Put both in `~/.hermes/.env` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`).

Telegram needs no inbound port; the bot polls outbound.

## 5. Microsoft Teams
Teams has to reach Jarvis over public HTTPS, which goes through xen-pxy.

1. **DNS and Caddy:** make sure `jarvis.xenspidey.com` resolves to your WAN IP (your wildcard may already cover it). Add `Caddyfile.snippet` to xen-pxy and reload Caddy.
2. **Register the bot** (as `jarvis` in the CT). Sign in with your CalenDynamics M365 account:
   ```bash
   teams login
   teams status --verbose       # copy your AAD object ID -> TEAMS_ALLOWED_USERS
   teams app create --name "Jarvis" --endpoint "https://jarvis.xenspidey.com/api/messages"
   ```
   Save `CLIENT_ID`, `CLIENT_SECRET` and `TENANT_ID` into `.env` right away; the secret is shown only once.
3. **Add the Teams extra** to Hermes (from the docs):
   ```bash
   python -c "import pm; pm.sync_venv(['teams'], explicit=True)"
   ```
   If `import pm` fails, run it from `~/.hermes/hermes-agent` using Hermes' own venv Python. The docs don't give the exact interpreter path.
4. After the gateway is running (step 6), install the app in Teams with `teams app get <teamsAppId> --install-link` and DM the bot.

## 6. Run the gateway as a service
Hermes won't install a *user* service inside a container, so use the system unit:
```bash
exit                         # back to root inside the CT
/home/jarvis/.local/bin/hermes gateway install --system --run-as-user jarvis
/home/jarvis/.local/bin/hermes gateway start --system
/home/jarvis/.local/bin/hermes gateway status --system
journalctl -u hermes-gateway -f
```
Then check:
```bash
curl http://localhost:3978/health                     # expect: ok
ss -ltnp | grep 3978                                   # see note below
curl -i https://jarvis.xenspidey.com/api/messages      # from outside: 401/405 is fine; 502 means Caddy can't reach the CT
```
**Bind-address note:** the docs show the proxy forwarding to `127.0.0.1:3978`. If `ss` shows 3978 bound only to `127.0.0.1`, xen-pxy (a different CT) can't reach it. In that case, check `hermes gateway` or `config.yaml` for a host/bind option, or run a small Caddy inside the Jarvis CT that forwards `:3978` to localhost.

## Security notes
- Jarvis has a shell. It's confined to its own unprivileged CT with no `/var/storage` mount. Keep it that way unless you deliberately give it access.
- Keep the allowlists set. The gateway denies unknown users by default; don't set `*_ALLOW_ALL_USERS=true`.
- `chmod 600 ~/.hermes/.env`. Rotate the Teams secret now and then.
- Updates: `su - jarvis -c "hermes update"`, then restart the gateway.
