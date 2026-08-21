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
| Bulk | **Samsung Portable SSD T5, 931.5 GB** (an SSD, not a spinning disk) → ext4, `/mnt/bulk`, 916 GB usable. Currently linked at **USB 2.0 / 480 Mb/s** — wrong port or cable, worth fixing before loading media |

## Environment specifics

- LAN is **`192.168.1.0/24`**, gateway `192.168.1.1`.
- Reach the box as **`homeserver.local`** (avahi/mDNS is installed). Always use
  `ssh -4` — mDNS answers with the IPv6 address and this ISP's IPv6 path is broken
  (see gotchas).
- Server user is **`hash`**, uid/gid **1000**. Passwordless sudo via
  `/etc/sudoers.d/hash-nopasswd`. SSH is key-only.
- Was on **Wi-Fi** (`wlp2s0`) at `192.168.1.198`. Owner is relocating the machine to
  the router to attach ethernet. The wired NIC needs its own DHCP reservation
  (different MAC), then `sudo rfkill block wifi` to avoid two default routes.
  NetworkManager (pulled in by Cockpit) will DHCP the wired NIC automatically; only
  `wlp2s0` is pinned in `/etc/network/interfaces`.
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

Host build is **complete and reboot-verified** (80 s to full recovery, `/mnt/bulk`
remounts, all containers return, no failed units).

- [x] Debian 13 installed
- [x] `01-base.sh` — zram 3.8G + 4G swapfile + 7.9G partition swap, sysctl, TZ
      America/New_York, NTP synced, journald capped, sleep masked
- [x] `03-docker.sh` — Docker 29.7.2, Compose v5.5.0, `edge` net on 172.28.0.0/16
- [x] `02-storage.sh /dev/sda` — T5 wiped (owner authorised), GPT + ext4 label `bulk`,
      fstab by UUID with `nofail`, full directory tree, USB autosuspend disabled
- [x] `04-remote-access.sh` — xrdp + XFCE on :3389, Cockpit on :9090, sshd key-only,
      fail2ban
- [x] `05-firewall.sh` — default deny in; only 51820/udp open to the internet
- [x] avahi/mDNS + `/etc/gai.conf` IPv4 preference (both now folded into `01-base.sh`)
- [x] `media` stack — plex (unclaimed, wizard pending) + audiobookshelf
- [x] `ops` stack — uptime-kuma + dozzle

Idle footprint: **1.1 GB used, 6.6 GB available** of 7.7 GB.

Next:

- [ ] Move machine to the router, attach ethernet, DHCP-reserve the wired MAC,
      `rfkill block wifi`
- [ ] Owner is buying a **domain for Cloudflare** — when it lands, set
      `CADDYFILE=Caddyfile` and `CF_DNS_API_TOKEN` in `stacks/edge/.env`.
      Recommended registrars: Cloudflare Registrar (~$10/yr .com, at cost) or Porkbun
- [ ] `edge` stack — blocked on that domain + token
- [ ] `vpn` stack — wg-easy. Owner CAN port-forward. Needs a DuckDNS-or-equivalent
      hostname for the public IP, and a bcrypt UI password hash
- [ ] `cloud` stack — Nextcloud. Only needs the domain settled first
- [ ] `download` stack — **blocked.** Owner has ProtonVPN **Free**, which blocks P2P
      and has no port forwarding, so gluetun would connect and torrents would never
      move. Needs a paid plan; suggested AirVPN / PIA / Proton Plus
- [ ] Plex settings pass (Remote Access OFF, LAN networks incl. 10.8.0.0/24, custom
      access URL, hardware transcoding — needs Plex Pass)
- [ ] `kalshi` stack — deploy from the owner's Windows box with
      `scripts/deploy-kalshi.ps1`
- [ ] `08-backups.md` — restic repo + systemd timer

## Gotchas already hit — fixed, but know why

| Symptom | Cause and fix |
|---|---|
| `intel-media-va-driver-non-free has no installation candidate` | It is in Debian's `non-free` component, off by default. Under `set -e` this aborted `01-base.sh` at step 1 so nothing after it ran. Now installed opportunistically. The package only affects host `vainfo` output — the Plex container ships its own VAAPI drivers |
| `permission denied` running a script | Git for Windows uses `core.filemode=false`, so exec bits were never recorded and clones landed at 644. Fixed with `git update-index --chmod=+x`. `bash scripts/foo.sh` is always the instant workaround |
| `refusing to operate on linked unit file smartd.service` | The real unit is `smartmontools.service`; `smartd.service` is a symlink alias. Fixed |
| CRLF risk | `.gitattributes` forces LF on everything the server executes (`.ps1` stays CRLF). A CRLF shebang fails with `bad interpreter: /bin/bash^M` |
| `ssh-copy-id: no identities found` | Was being run on the *server*, which has no keys. It runs on the client. Windows' bundled OpenSSH has no `ssh-copy-id` either — only Git Bash does |
| Docker pulls die partway with `connection reset by peer` on a `2600:...` address | This ISP's **IPv6** path to the registry resets mid-transfer. Fixed with `precedence ::ffff:0:0/96 100` in `/etc/gai.conf`. Same reason to prefer `ssh -4` |
| `sgdisk: command not found` in the storage script | `gdisk` and `parted` are not on a minimal Debian. The script now installs them |
| DuckDNS cannot do per-subdomain certs | It only writes the ACME TXT at the domain root, so a wildcard cert is mandatory — that is why `Caddyfile.duckdns` is one site block with Host matchers instead of many site blocks |
| `git pull` refused: local changes | Mode-only diffs (`100644 => 100755`) from the owner's manual `chmod +x`, against an index that predated the exec-bit commit. `git checkout -- scripts/` was safe: zero content changes |

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
