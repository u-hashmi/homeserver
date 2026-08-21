# CLAUDE.md — homeserver

Project memory. Auto-loaded by Claude Code. Read `README.md` for the architecture and
the `docs/` build order; this file carries the state and the hard-won details that are
not obvious from the files.

## What this is

Converting a **Lenovo ThinkCentre M910q Tiny** into a 24/7 home server: Nextcloud
(+ Notes), Plex (for Plexamp and the Prologue iOS audiobook client), Audiobookshelf,
a WireGuard VPN, an *arr + qBittorrent download stack behind a commercial VPN, and
the owner's **kalshi-flipper** trading bot.

Repo layout: `docs/` numbered build guide, `scripts/` idempotent host setup,
`stacks/` one Docker Compose stack per concern.

## Hardware

| | |
|---|---|
| CPU | i5-6500T, 4C/4T, 35 W. Intel HD 530 → QuickSync (H.264, HEVC 8-bit) |
| RAM | **8 GB.** Full stack idles ~3.2 GB. 16 GB (2× 8 GB DDR4-2400 SODIMM) recommended but explicitly deferred — owner is not ordering yet |
| SSD | 256 GB internal → `/srv/apps/*`, all databases, OS |
| Bulk | 1 TB external USB3, permanently attached → `/mnt/bulk/*`, media + Nextcloud files + backups |

## Environment specifics

- LAN is **`192.168.1.0/24`**, gateway `192.168.1.1`.
- Currently on **Wi-Fi** (`wlp2s0`), DHCP address `192.168.1.198`. Owner will plug in
  ethernet later; the wired NIC needs its own DHCP reservation (different MAC), and
  `sudo rfkill block wifi` afterwards to avoid two default routes.
- The IP must be pinned **before** the `edge` stack is configured — that is where the
  address gets baked into the wildcard DNS record, Plex's custom access URL, the
  router port forward and `deploy-kalshi.ps1`.
- Owner cannot easily reach the router physically, but its admin UI is reachable at
  `http://192.168.1.1` from any device on the LAN.
- Bot repo lives at `D:\AI\kalshi-flipper` on the owner's Windows box; it deploys to
  `/srv/apps/kalshi/kalshi-flipper` on the server.
- This repo is cloned to **`/srv/homeserver`** on the server. `scripts/kalshi.sh` and
  `scripts/backup.sh` hardcode that path.

## Decisions already made — do not relitigate

- **Debian 13 bare metal**, not Windows and not Proxmox. Idle RAM and native
  `/dev/dri` passthrough for Plex decided it.
- **WireGuard-only ingress.** One forwarded port (51820/udp). Nothing else is exposed,
  which is why the web UIs are not internet-hardened. Plex Remote Access stays OFF.
- **No Tor.** The owner originally asked for it. WireGuard covers remote access, and
  torrenting over Tor is unusably slow and harmful to that network. The download path
  uses a commercial VPN (gluetun) instead. This was discussed and settled.
- **Plex is not reverse-proxied.** Host network, `:32400`, its own TLS via
  `*.plex.direct`. Proxying breaks client discovery for no gain.
- **No databases on `/mnt/bulk`.** Postgres and WAL-mode SQLite on a removable USB bus
  corrupt. Internal SSD only, always.
- **Container updates are manual** (`scripts/update.sh`); only Debian *security*
  patches auto-install.
- **Nextcloud upgrades one major at a time** via `NEXTCLOUD_TAG` in `stacks/cloud/.env`.
  It refuses to skip a major.
- **TLS** is Let's Encrypt over a Cloudflare DNS-01 challenge, with the domain's A
  records pointing at the *private* LAN IP. Real certs, zero exposure.
  `stacks/edge/Caddyfile.internal` is the no-domain fallback.
- The `edge` docker network is pinned to `172.28.0.0/16` because gluetun's killswitch
  must be told that range is allowed.

## Build progress

Done:

- [x] Debian 13 installed. "standard system utilities" was missed at the installer and
      recovered with `tasksel install standard`.
- [x] `scripts/01-base.sh` — packages, zram + 4 GB swapfile, sysctl, journald caps,
      unattended security upgrades, sleep masked.
- [x] Repo pushed to `github.com/u-hashmi/homeserver` and cloned to `/srv/homeserver`.

Next, in order:

- [ ] SSH key into `~/.ssh/authorized_keys` (in progress — needed before hardening)
- [ ] `scripts/03-docker.sh`, then log out/in, then `docker run --rm hello-world`
- [ ] `scripts/04-remote-access.sh` (XRDP + XFCE + Cockpit + sshd hardening)
- [ ] `LAN=192.168.1.0/24 scripts/05-firewall.sh`
- [ ] `scripts/02-storage.sh /dev/sdX` — format + mount the 1 TB
- [ ] Ethernet cable, DHCP reservation, `rfkill block wifi`
- [ ] `docs/06-services.md` — edge, vpn, cloud, media, download stacks
- [ ] `docs/07-kalshi-bot.md` — deploy the bot
- [ ] `docs/08-backups.md` — restic repo + systemd timer

## Gotchas already hit — fixed, but know why

| Symptom | Cause and fix |
|---|---|
| `intel-media-va-driver-non-free has no installation candidate` | It is in Debian's `non-free` component, off by default. Under `set -e` this aborted `01-base.sh` at step 1 so nothing after it ran. Now installed opportunistically. The package only affects host `vainfo` output — the Plex container ships its own VAAPI drivers |
| `permission denied` running a script | Git for Windows uses `core.filemode=false`, so exec bits were never recorded and clones landed at 644. Fixed with `git update-index --chmod=+x`. `bash scripts/foo.sh` is always the instant workaround |
| `refusing to operate on linked unit file smartd.service` | The real unit is `smartmontools.service`; `smartd.service` is a symlink alias. Fixed |
| CRLF risk | `.gitattributes` forces LF on everything the server executes (`.ps1` stays CRLF). A CRLF shebang fails with `bad interpreter: /bin/bash^M` |
| `ssh-copy-id: no identities found` | Was being run on the *server*, which has no keys. It runs on the client. Windows' bundled OpenSSH has no `ssh-copy-id` either — only Git Bash does |

## Conventions

- Every script is **idempotent** and safe to re-run. Keep it that way.
- Scripts refuse to run as root and `sudo` internally.
- `scripts/up.sh` refuses to start a stack whose `.env` is missing rather than starting
  it with silent defaults.
- Secrets: only `*.env.example` is tracked. `.gitignore` covers `stacks/*/.env`. Never
  commit a real `.env`, a `.pem`, or a token.
- Git identity in this repo is **local**: `Hash <hash.design.develop@gmail.com>`. The
  owner's global identity is a work address — do not let it into commits here.
- The download stack is general-purpose automation. Do not add indexers or content
  suggestions; that is the owner's call.

## Owner's stated preferences

Direct and brief. Answer the question asked, lead with the command or the code, skip
preamble, apologies and filler. No enthusiasm. If something is wrong, say so in a
sentence and keep going.
