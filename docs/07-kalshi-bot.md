# 07 — Kalshi-Flipper on the home server

The bot repo already ships a Linux Compose stack built for a single VM: `bot-live`,
`bot-paper`, and a Caddy that serves the React dashboard and puts Basic Auth over
`/api` and `/ws`. Almost nothing needs to change — the one conflict is that its Caddy
wants host ports 80/443, which belong to the `edge` stack here.

`stacks/kalshi/docker-compose.override.yml` resolves that:

| Override | Effect |
|---|---|
| `ports: !reset null` | Nothing published on the host; reachable only on the `edge` network |
| `SITE_ADDRESS=:80` | Plain HTTP inside the network — edge Caddy terminates TLS |
| `container_name: kalshi-caddy` | Stable hostname for edge's `reverse_proxy` target |

The repo's Basic Auth stays enabled. Layered: WireGuard, then TLS, then the login.

```
edge Caddy ──TLS──▶ kalshi-caddy:80 ──┬─▶ /srv/web        (dashboard)
   kalshi.<domain>    (Basic Auth)     └─▶ bot-live:8080   (/api, /ws)
                                          bot-paper:8081  (paper instrument)
                                          data/flipper.db (shared SQLite, on the SSD)
```

## Why here and not the cloud

The trade-off is honest, and worth stating before you move it:

- **Better:** free, no VM to pay for, full CPU, the SQLite and Parquet archives live
  on a disk you own, and you can attach a debugger over RDP.
- **Worse:** your home internet and power are now the bot's SLA, and you are ~1
  network hop further from Kalshi than an Ashburn VM. For the flip catcher — which
  enters in the last ~180s of a 15-minute cycle on rule-based gates, not
  microseconds — home latency is fine. If you ever move to a strategy that races
  other bots on fills, move it back to a VM near Ashburn.
- Mitigations that matter: wired ethernet, a UPS, and BIOS *After Power Loss →
  Power On* so an outage self-heals.

## First deploy

### 1. Secrets

These are git-ignored and must exist on your Windows box before deploying:

```
D:\AI\kalshi-flipper\keys\.env          KALSHI_API_KEY_ID, KALSHI_API_KEY, DISCORD_WEBHOOK_*
D:\AI\kalshi-flipper\keys\kalshi.pem    the Kalshi private key
D:\AI\kalshi-flipper\deploy\live.env    CATCHER_* strategy config, loss caps, rate limits
D:\AI\kalshi-flipper\deploy\paper.env   same, paper
D:\AI\kalshi-flipper\deploy\proxy.env   SITE_ADDRESS, BASIC_AUTH_USER, BASIC_AUTH_HASH
```

Missing any of the `.env` files? Copy from the matching `.example`. For the dashboard
password hash:

```powershell
docker run --rm caddy:2-alpine caddy hash-password --plaintext 'YOUR_PASSWORD'
```

`SITE_ADDRESS` in `proxy.env` no longer matters — the override forces `:80`.

> **Double every `$` in `BASIC_AUTH_HASH`.** Docker Compose v5 interpolates
> `env_file` values, so a raw bcrypt hash like `$2a$14$Ryh...` gets `$Ryh...`
> treated as an undefined variable and blanked, leaving `$2a$14$` — and Caddy
> then rejects every login with `bcrypt: hashedSecret too short`. Write it as
> `$$2a$$14$$Ryh...`. This fails silently by truncating the secret, so the only
> symptom is a permanent 401.
>
> Forgotten the password? Bcrypt is one-way — it cannot be recovered, only reset:
>
> ```bash
> PW=$(openssl rand -base64 15 | tr -d '/+=' | cut -c1-16); echo "$PW"
> docker run --rm caddy:2-alpine caddy hash-password --plaintext "$PW"
> # put the hash in deploy/proxy.env with every $ doubled, then:
> docker compose ... up -d --force-recreate caddy
> ```

### 2. Ship it

From Windows, in `D:\AI\HomeServer`:

```powershell
.\scripts\deploy-kalshi.ps1 -ServerHost 192.168.1.50 -User hash
```

It preflights the secrets (including the two traps below), collects the source with
**`git archive`**, uploads it, fixes ownership, and builds on the server.

Why `git archive` rather than `tar`: the working tree carries gigabytes of untracked
Parquet tick archives — `du` on it times out, let alone a tar. `git archive HEAD`
emits exactly the tracked files (~1 MB) by construction, so `data/` and the `.exe`
builds are excluded without a guessed exclude list. The server keeps its own SQLite;
shipping yours would clobber live trade history.

It also writes a temp file and `scp`s it instead of piping tar, because PowerShell
re-encodes bytes as text between native commands and corrupts a gzip stream.

**Ownership matters.** The image runs as **uid 10001 (`app`)**:

| Path | Owner | Mode | Why |
|---|---|---|---|
| `data/` | `10001:10001` | 755 | Must be writable, or SQLite fails with `unable to open database file: out of memory (14)` — error 14 is `CANTOPEN`, not OOM |
| `keys/`, `deploy/` | `<you>:10001` | 750 / 640 | Container reads via group; you keep ownership so `kalshi.sh`'s preflight still works. `chmod 700` here locks out the script itself |

Re-run the same command for every subsequent deploy. It is idempotent and the
database persists.

### 3. Or from the server directly

```bash
sudo mkdir -p /srv/apps/kalshi && sudo chown $USER:$USER /srv/apps/kalshi
cd /srv/apps/kalshi
git clone <your-fork> kalshi-flipper
# copy the five secret files in by hand (they are not in git), then:
/srv/homeserver/scripts/kalshi.sh up
```

## Operating it

```bash
./scripts/kalshi.sh up               # build + (re)start
./scripts/kalshi.sh logs             # follow both bots
./scripts/kalshi.sh restart bot-live # restart just the live bot
./scripts/kalshi.sh down             # stop
./scripts/kalshi.sh ps
```

Dashboard: `https://kalshi.<domain>` over WireGuard or on the LAN.

## Things to get right

**Clock.** The catcher works in the final seconds of a cycle; a drifting clock is a
silent losing strategy. `01-base.sh` enables NTP. Verify:

```bash
timedatectl status | grep -E 'synchronized|NTP'      # both should say yes/active
```

**Timezone.** Set `TZ_NAME=America/New_York` when you run `01-base.sh`, and keep the
container timezones matching, so log timestamps line up with Kalshi's cycles.

**SQLite stays on the SSD.** The repo mounts `./data` relative to itself, and the repo
lives at `/srv/apps/kalshi/kalshi-flipper` on the internal SSD. Never relocate it to
`/mnt/bulk` — WAL-mode SQLite on a removable USB bus is how you lose trade history.

**It survives reboots.** The services are `restart: unless-stopped`, Docker is enabled
at boot, and BIOS brings the machine back after a power cut. Test it once:

```bash
sudo reboot
# then, after it comes back
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

**Alerts.** `bot-live` runs with `ALERTS_ENABLED=1` and posts to your Discord
webhook; `bot-paper` is deliberately silent. Add an Uptime Kuma monitor on the
dashboard URL too, so you find out when the *box* is down — the bot cannot alert you
about its own machine being unreachable.

**Backups.** `scripts/backup.sh` snapshots `flipper.db` with SQLite's `.backup`
command (the only safe way to copy a live WAL database) and includes the whole repo
directory, so config and trade history both survive a disk failure.

## Resource footprint

Two Go binaries plus a Caddy: roughly 150 MB resident and negligible CPU between
cycles. The Python ML sidecar is not deployed — the flip catcher is rule-based and
never calls it, exactly as the repo's cloud stack intends. If you later want the ML
scorer running here, it is a separate compose service and will want another ~600 MB,
which is an argument for the 16 GB upgrade.
