# HomeServer — Lenovo ThinkCentre M910q Tiny

Debian 13 + Docker Compose home server. Everything is LAN-only; the single door in
from the internet is WireGuard (one forwarded UDP port).

```
                    internet
                       │  51820/udp  ← the ONLY forwarded port
                       ▼
                  ┌─────────┐
                  │ wg-easy │  WireGuard server (phone / laptop dial in)
                  └────┬────┘
                       │  10.8.0.0/24  +  LAN 192.168.x.0/24
   ┌───────────────────┴──────────────────────────────────────────┐
   │  M910q  (Debian 13, docker)                                  │
   │                                                              │
   │  caddy :443 ──┬─ nextcloud.<domain>   Nextcloud + Notes       │
   │               ├─ books.<domain>       Audiobookshelf          │
   │               ├─ kalshi.<domain>      Kalshi-Flipper dash     │
   │               ├─ sonarr|radarr|…      *arr stack              │
   │               └─ wg.<domain>          wg-easy UI              │
   │                                                              │
   │  plex :32400 (host net, QuickSync)   ← Plex / Plexamp / Prologue
   │  xrdp :3389  (XFCE desktop)          ← mstsc.exe / Remmina    │
   │  cockpit :9090                       ← web server admin       │
   │  sshd :22                                                     │
   │                                                              │
   │  gluetun (commercial VPN) ── qbittorrent + prowlarr          │
   │  bot-live / bot-paper                Kalshi-Flipper           │
   └──────────────────────────────────────────────────────────────┘
        /            (256 GB internal SSD)  OS, configs, all databases
        /mnt/bulk    (1 TB external USB3)   media, Nextcloud files, backups
```

## Build order

Follow the docs in order. Each script is idempotent — safe to re-run.

| # | Doc | What happens |
|---|-----|--------------|
| 0 | [docs/00-hardware.md](docs/00-hardware.md) | RAM/disk check, BIOS settings, upgrade shopping list |
| 1 | [docs/01-debian-install.md](docs/01-debian-install.md) | Wipe Windows, install Debian 13 |
| 2 | [docs/02-host-setup.md](docs/02-host-setup.md) | `01-base.sh`, `03-docker.sh`, `05-firewall.sh` |
| 3 | [docs/03-remote-access.md](docs/03-remote-access.md) | SSH keys, XRDP desktop, Cockpit — `04-remote-access.sh` |
| 4 | [docs/04-storage.md](docs/04-storage.md) | Format + mount the 1 TB, create the directory tree — `02-storage.sh` |
| 5 | [docs/05-wireguard.md](docs/05-wireguard.md) | wg-easy, router port-forward, DDNS, client configs |
| 6 | [docs/06-services.md](docs/06-services.md) | Bring up edge / cloud / media / download / ops stacks |
| 7 | [docs/07-kalshi-bot.md](docs/07-kalshi-bot.md) | Deploy Kalshi-Flipper from your Windows box |
| 8 | [docs/08-backups.md](docs/08-backups.md) | restic + Postgres dumps + SQLite snapshots |
| 9 | [docs/09-operations.md](docs/09-operations.md) | Updates, logs, RAM budget, troubleshooting |

## What runs where

| Stack | Services | Host port | Notes |
|-------|----------|-----------|-------|
| `edge` | Caddy, ddns-updater | 80, 443 | TLS + single entry point for every web UI |
| `vpn` | wg-easy | 51820/udp, 51821 | The remote-access VPN (inbound) |
| `cloud` | Nextcloud, Postgres, Redis, cron | — | Notes app installed in-app after first login |
| `media` | Plex, Audiobookshelf | 32400 | Plex on host network for discovery + QuickSync |
| `download` | gluetun, qBittorrent, Prowlarr, Sonarr, Radarr, Bazarr | — | All download traffic forced through a commercial VPN |
| `kalshi` | bot-live, bot-paper, kalshi-caddy | — | Compose override on top of the bot repo's own file |
| `ops` | Uptime Kuma, Dozzle | — | Optional. Drop these first if RAM gets tight |

## Decisions and why

- **Debian 13 bare metal, not Windows or Proxmox.** ~400 MB idle instead of ~3 GB,
  `/dev/dri` passes straight into the Plex container for QuickSync transcoding, and
  the Kalshi bot's existing Linux compose file runs unchanged.
- **WireGuard-only ingress.** Nothing else is reachable from the internet, so no web
  UI needs to be internet-hardened. Plex remote access is turned **off** on purpose —
  Plexamp and Prologue reach it over the tunnel.
- **No Tor.** You mentioned it, so to be explicit: it buys nothing here. WireGuard
  already covers remote access, and Tor is a bad transport for torrents (it is
  actively harmful to the network and gives unusable speeds). The download stack uses
  a commercial WireGuard VPN with a killswitch instead — see
  [docs/06-services.md](docs/06-services.md#download--vpn-killswitch).
- **Databases never live on the USB drive.** SQLite and Postgres on a removable bus
  is how you get corruption. Internal SSD only; bulk files on `/mnt/bulk`.
- **Valid TLS with no open ports.** Caddy gets Let's Encrypt certs over a Cloudflare
  DNS-01 challenge, and your domain's A records point at the server's *private* LAN
  IP. Real certs, zero exposure. `Caddyfile.internal` is the fallback if you'd rather
  not own a domain.

## Legal note

The `download` stack is general-purpose automation software. What you point it at is
on you — keep it to content you have the right to.
