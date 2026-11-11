# Jarvis (Hermes Agent) on the R730

Unprivileged Debian 13 LXC, `jarvis` service user, Anthropic API, and three ways to talk to it: terminal, Telegram and Teams.

Checked against the source of Hermes Agent **stable v0.23.1** (installer, Teams adapter, `hermes pm`, gateway service) and Teams CLI **3.1.0**. It hasn't been run on the R730 yet, so if a step doesn't match what you see, stop and note it.

## 1. Copy the kit to the R730 host
From your PC (PowerShell or bash). Don't put a trailing slash on the source folder: Windows' scp then fails with "path canonicalization failed".
```bash
scp -r jarvis root@192.168.128.172:/root/jarvis
```
The repo's `.gitattributes` keeps LF line endings even in a Windows clone. On the host, `grep -c $'\r' /root/jarvis/*.sh` should print `0` for every file.

## 2. Create the container (on the host)
Check the variables at the top of `01-create-lxc.sh` (storage, bridge, IP). Caddy on xen-pxy points at the CT's IP, so either set a static `IP_CFG` or reserve the DHCP lease on your router afterwards. Then:
```bash
cd /root/jarvis && chmod +x *.sh && ./01-create-lxc.sh
```
This creates the CT, installs Hermes for user `jarvis`, pre-installs the Anthropic/Telegram/Teams extras, drops in `SOUL.md` (the Jarvis persona), adds a secrets block to `~/.hermes/.env`, and installs the Teams CLI. It ends with a banner showing the VMID and IP.

- Scroll back for any `!! WARNING` lines. Each one says what to re-run.
- If the bootstrap fails, the CT stays. Fix the cause and re-run `pct exec <VMID> -- /root/02-bootstrap.sh` (it's safe to repeat). Re-running `01-create-lxc.sh` refuses to make a second `xen-jarvis`.

Quick check from the host:
```bash
pct exec <VMID> -- su - jarvis -c 'hermes --version; teams --version'
```

## 3. Model: Anthropic
```bash
pct enter <VMID>
su - jarvis
nano ~/.hermes/.env          # kit block is at the END (Alt+/ jumps there); paste ANTHROPIC_API_KEY
hermes model                 # pick Anthropic and a Claude model
hermes                       # say hi; check that it introduces itself as Jarvis
hermes doctor
```
This is the terminal option. From now on, `ssh` → `pct enter` → `su - jarvis` → `hermes`.

The installer wrote `~/.hermes/.env` from Hermes' own example (mostly comments plus a few defaults). Leave that part alone and fill in the kit block at the bottom.

## 4. Telegram
1. Telegram → @BotFather → `/newbot` (the username must end in `bot`). Copy the token.
2. Message @userinfobot to get your numeric ID.
3. Put both in `~/.hermes/.env` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`).

Telegram needs no inbound port; the bot polls outbound. With no allowlist set, the gateway denies everyone.

## 5. Microsoft Teams (do this before step 6)
Teams has to reach Jarvis over public HTTPS, which goes through xen-pxy.

**Why before step 6:** `teams login` stores your M365 sign-in in a plaintext file in jarvis' home (a headless CT has no keyring). The agent runs as jarvis and could read that file. So register the bot while the gateway isn't running, then log out.

1. **DNS and Caddy:** make sure `jarvis.xenspidey.com` resolves to your WAN IP (your wildcard may already cover it). Add `Caddyfile.snippet` to xen-pxy with `JARVIS_IP` replaced by the CT's IP, and reload Caddy.
2. **Register the bot** (as `jarvis` in the CT). Sign in with your CalenDynamics M365 account:
   ```bash
   teams login --device-code    # open the printed URL on your PC and enter the code
   teams status --verbose       # "User Object ID" -> TEAMS_ALLOWED_USERS
   teams app create --name "Jarvis" --endpoint "https://jarvis.xenspidey.com/api/messages"
   ```
   `app create` asks you to confirm, then prints the **Install in Teams** link, the **Teams App ID**, and the credentials. Save them right away; the secret is shown only once:

   | CLI prints | Put in `~/.hermes/.env` |
   |---|---|
   | `CLIENT_ID=` | `TEAMS_CLIENT_ID=` |
   | `CLIENT_SECRET=` | `TEAMS_CLIENT_SECRET=` |
   | `TENANT_ID=` | `TEAMS_TENANT_ID=` |

   Copy the install link somewhere too (you'll open it in step 6). At the menu that follows, pick **Done**. The other options try to open a browser inside the CT.
3. **Log out** so no M365 token stays in jarvis' home:
   ```bash
   teams logout
   rm -f ~/.config/teams-cli/msal-cache.json
   ```
   The CLI's warning *"libsecret not found — token cache will be stored unencrypted. Install … libsecret-1-dev"* is expected here. Installing that package won't help without a keyring daemon, which is why you log out instead.
4. **Teams extra:** the bootstrap already ran `hermes pm install --extra teams`. Only if it printed a warning, run it again as jarvis.

Lost the install link? `teams login --device-code`, then `teams app get <teamsAppId> --install-link`, then step 3 again.

`teams` here is a small wrapper (`~/.local/bin/teams`) that runs the CLI on Hermes' own Node. Debian's `nodejs` isn't used, because the CLI needs Node ≥ 22.12.

## 6. Run the gateway as a service
Hermes won't install a *user* service inside a container, so use the system unit:
```bash
exit                         # back to root inside the CT
/home/jarvis/.local/bin/hermes gateway install --system --run-as-user jarvis
/home/jarvis/.local/bin/hermes gateway start --system
/home/jarvis/.local/bin/hermes gateway status --system
journalctl -u hermes-gateway -f
```
In the log, look for `[teams] Webhook server listening on * (all interfaces, IPv4+IPv6):3978/api/messages`, plus the Telegram adapter connecting.

Then check:
```bash
curl http://localhost:3978/health                     # expect: ok
ss -ltnp | grep 3978                                   # expect *:3978 / [::]:3978, NOT 127.0.0.1
find /home/jarvis ! -user jarvis                       # expect no output
```
From xen-pxy: `curl http://JARVIS_IP:3978/health` → `ok`. From outside: `curl -i https://jarvis.xenspidey.com/api/messages` → `405` is correct (the route only accepts POST). `502` means Caddy can't reach the CT.

Finally, open the install link from step 5 on your PC and DM the bot. It should answer as Jarvis. A message from an account that isn't in `TEAMS_ALLOWED_USERS` is silently dropped.

**Bind address:** the Teams listener binds all interfaces by default, so xen-pxy can reach it. `TEAMS_HOST` would pin it, but don't set it to `127.0.0.1`. Bot Framework requests are JWT-checked. Optional hardening is a Proxmox firewall rule that allows 3978 into this CT only from xen-pxy.

## Updates
```bash
su - jarvis -c "hermes update"
/home/jarvis/.local/bin/hermes gateway restart --system      # as root; jarvis has no sudo to do it
```

## Security notes
- Jarvis has a shell. It's confined to its own unprivileged CT with no `/var/storage` mount, and `jarvis` has no sudo. Keep it that way unless you deliberately give it access.
- Keep the allowlists set. The gateway denies unknown users by default; don't set `*_ALLOW_ALL_USERS=true` or `GATEWAY_ALLOW_ALL_USERS=true`.
- `chmod 600 ~/.hermes/.env`. To rotate the Teams secret: `teams login --device-code`, `teams app auth secret create <teamsAppId>`, put the new value in `.env`, restart the gateway, then log out as in step 5.
- Don't leave the Teams CLI logged in (see step 5).
