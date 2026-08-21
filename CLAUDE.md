# CLAUDE.md — homeserver

Project memory. Auto-loaded by Claude Code. Read `README.md` for the architecture and
the `docs/` build order; this file carries the state and the hard-won details that are
not obvious from the files.

## What this is

Converting a **Lenovo ThinkCentre M910q Tiny** into a 24/7 home server: Nextcloud
(+ Notes), Plex (movies/TV, plus the Prologue iOS audiobook client), Audiobookshelf,
a WireGuard VPN, an *arr + qBittorrent download stack behind a commercial VPN, and
the owner's **kalshi-flipper** trading bot.

Repo layout: `docs/` numbered build guide, `scripts/` idempotent host setup,
`stacks/` one Docker Compose stack per concern.

## Hardware

| | |
|---|---|
| CPU | i5-**7500T** (Kaby Lake), 4C/4T, 35 W. Intel HD 630 → QuickSync: H.264 decode+encode, **HEVC Main10 decode** (verified via vainfo). No HEVC encode |
| RAM | **8 GB.** Full stack idles ~3.2 GB. 16 GB (2× 8 GB DDR4-2400 SODIMM) recommended but explicitly deferred — owner is not ordering yet |
| SSD | 256 GB internal → `/srv/apps/*`, all databases, OS |
| Bulk | **Samsung Portable SSD T5, 931.5 GB** (an SSD, not a spinning disk) → ext4, `/mnt/bulk`, 916 GB usable. Currently linked at **USB 2.0 / 480 Mb/s** — wrong port or cable, worth fixing before loading media |

## 4K: what this hardware can and cannot do

The listing said i5-6500T (Skylake); the machine is actually an **i5-7500T
(Kaby Lake)**. That matters: Kaby Lake added HEVC 10-bit decode, which Skylake
lacks. `vainfo` on the host confirms `HEVCMain10: VAEntrypointVLD` (decode) and
`H264High: VAEntrypointEncSliceLP` (encode) -- exactly the pipeline a 4K->1080p
transcode needs. There is **no HEVC encode**.

- **4K direct play: fine.** The server only moves bytes.
- **4K transcode: hardware-capable but needs Plex Pass**, which the owner does not
  have (`myPlexSubscription=0`). Without it, software HEVC decode of 4K on 4 cores
  will stutter.
- **Storage is the binding constraint**: 907 GB free means ~10-14 4K remuxes, or
  ~35-60 4K WEB-DLs, or ~60-110 1080p files.
- **Remote 4K over WireGuard is limited by upload**, not the server. A remux at
  60-90 Mbps will not fit residential upload.
- Transcode scratch is `/dev/shm` at 3.9 GB. Fine for 1080p; move it to the T5
  before attempting 4K transcodes.

Current profile is quality id 6 (HD 720p/1080p) on both Radarr and Sonarr.

## Environment specifics

- LAN `192.168.1.0/24`, gateway `192.168.1.1`. Server is **static `192.168.1.50`**
  on ethernet (`enp0s31f6`, gigabit, NetworkManager profile "Wired connection 1").
  Wi-Fi is disabled (`nmcli radio wifi off`, and `allow-hotplug wlp2s0` commented
  out in `/etc/network/interfaces`).
- Reach it as `homeserver.local` or `192.168.1.50`. **Always `ssh -4`** -- see the
  IPv6 note in gotchas.
- User **`hash`**, uid/gid **1000**, passwordless sudo, SSH key-only.
- Domain **`coder-geist.com`** on Cloudflare (zone `0fc2799adb1ca794059e2ee2ddf02a4a`,
  account `f1e538439bc4e85979b5269804d7cfb8`). Services live under
  **`home.coder-geist.com`**; the apex and `www` are deliberately free for a future
  public site.
  - `home.coder-geist.com` + `*.home.coder-geist.com` -> `192.168.1.50` (DNS-only)
  - `vpn.coder-geist.com` -> public IP, kept current by `ddns-updater`
  - The Cloudflare token is **account-owned**, so it 401s at `/user/tokens/verify`
    and must use `/accounts/<id>/tokens/verify`.
- Public IP moves: `173.40.32.72` then `66.168.9.180` within one evening. That is
  why `ddns-updater` exists. ISP is **Spectrum**; the router is a Sagemcom managed
  through the **My Spectrum app** (Services -> Router -> Advanced Settings ->
  Port Forwarding & IP Reservations).
- Bulk disk is a **Samsung Portable SSD T5**, ext4, `/mnt/bulk`, currently
  `/dev/sdb1` (it was `sda` before a cable swap -- never hardcode the device node).
  Now on a USB 3 link: **245 MB/s** measured, up from ~40 MB/s on USB 2.
- Bot repo is at `D:\AI\kalshi-flipper` on the owner's Windows box; it deploys to
  `/srv/apps/kalshi/kalshi-flipper`.
- This repo is cloned to **`/srv/homeserver`**. `scripts/kalshi.sh`,
  `scripts/backup.sh` and the systemd units hardcode that path.

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

Host build and all six stacks are **live and verified**. 16 containers running,
**1.7 GB used of 7.7 GB**. Every service URL returns valid TLS
(`ssl_verify_result=0`) from outside the box.

Done:

- [x] Debian 13, `01-base.sh`, `03-docker.sh`, `04-remote-access.sh`, `05-firewall.sh`
- [x] `02-storage.sh /dev/sda` -- T5 wiped and ext4, 916 GB at `/mnt/bulk`
- [x] Static IP `.50`, Wi-Fi off, single default route
- [x] **edge** -- Caddy built with cloudflare+duckdns modules, ONE wildcard cert for
      `*.home.coder-geist.com`, auto-renewing, zero ports opened to obtain it
- [x] **cloud** -- Nextcloud 31.0.14 + Postgres 17 + Redis; Notes, Calendar,
      Contacts, Tasks enabled; both setup warnings cleared; data on the T5
- [x] **media** -- Plex (unclaimed, wizard still pending) + Audiobookshelf
- [x] **ops** -- Uptime Kuma + Dozzle
- [x] **vpn** -- wg-easy on 51820/udp + ddns-updater on Cloudflare
- [x] **download** -- gluetun/PIA (OpenVPN, CA Montreal) + qBittorrent + Prowlarr
      inside the netns; Sonarr/Radarr outside. Killswitch verified: host
      `66.168.9.180` vs qbt/prowlarr `140.228.24.x`. Root folders and the
      qBittorrent client wired; Prowlarr knows both apps.
- [x] `qbt-port-sync` systemd timer (10 min) reconciling PIA's forwarded port

Credentials issued (all in git-ignored `.env` files, mode 600):

| Service | User | Password |
|---|---|---|
| Nextcloud | `hash` | `ejVxDF3xsPC78ABUQiW1mR` |
| qBittorrent | `admin` | `2xUzyGVH2wjwuCUV` |
| wg-easy UI | -- | `8idZCLtlexHsw8rO` |

Next:

- [ ] **Router**: confirm UDP 51820 is forwarded to `.50`. Until then WireGuard
      works on the LAN only. Also check for CGNAT -- if the router's WAN IP is
      `100.64.x.x`-`100.127.x.x`, port forwarding cannot work and the plan is to
      swap wg-easy for Tailscale.
- [ ] WireGuard peers (wg-easy UI, QR codes)
- [x] Plex Watchlist -> auto-download wired: `PlexImport` import lists on both
      Radarr and Sonarr, quality profile 6 (HD 720p/1080p), `searchOnAdd` on,
      Sonarr `shouldMonitor=all`, `listSyncLevel=disabled` so un-watchlisting
      never deletes files. ImportListSync runs every 5 minutes.
- [x] Plex claimed and configured: Remote Access + Relay OFF, LAN Networks
      `192.168.1.0/24,10.8.0.0/24`, custom access URL `http://192.168.1.50:32400`,
      transcode dir `/transcode`, Butler window 3-5am, FS-event scanning on, and
      three libraries (Movies, TV, Audiobooks) on `/data/library/*` -- the Music
      library was removed since the owner does not use Plexamp.
      **No Plex Pass** (`myPlexSubscription=0`) so QuickSync stays inactive --
      set clients to Original quality so they direct-play.
- [x] Sonarr/Radarr notify Plex on import (needed a ufw rule: containers reach
      host-network Plex from 172.28.x.x, which no existing rule covered)
- [ ] Prowlarr indexers -- the owner's choice, do not pick for them
- [x] **kalshi** stack deployed **live + paper** (owner's explicit choice after the
      real-money warning). Kalshi WS + Coinbase + Kraken feeds connected, SQLite in
      WAL mode on the internal SSD, dashboard behind the house proxy at
      `kalshi.home.coder-geist.com` with the repo's own Basic Auth intact.
- [x] Backups: restic repo on the T5, nightly systemd timer at 04:23, restore
      tested. **The passphrase is at `/root/.restic-password` and must be copied
      off the machine** -- a repo whose only key lives on the disk it protects is
      not a backup.
- [x] Download chain verified end to end: owner added 4 indexers in Prowlarr, all
      testing valid, live search returns results through the VPN. Radarr/Sonarr
      have the indexers, qBittorrent as client, root folders, Plex notification on
      import, and Plex-friendly rename formats. Adding a movie is now fully
      automatic through to the Plex library.
- [ ] Optional: 16 GB RAM; Bazarr (behind the `full` profile)

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
| Docker pulls die mid-transfer on a `2600:...` address | This ISP's IPv6 path resets and times out. `/etc/gai.conf` fixes the C resolver but **Go ignores gai.conf**, so dockerd kept choosing IPv6. Real fix: `net.ipv6.conf.all.disable_ipv6=1` in `/etc/sysctl.d/99-disable-ipv6.conf`. Same reason to use `ssh -4` |
| Nextcloud: "Cannot create or write into the data directory" | `/mnt/bulk/nextcloud-data` must be **uid 33 (www-data)**, not PUID 1000. And the image only auto-installs while `/var/www/html` is empty, so restarting never retries -- finish with `occ maintenance:install` |
| Nextcloud: "Cannot write into config directory", every occ command fails | Caused by re-running `02-storage.sh` while it still did `chown -R /srv/apps` to PUID. The containers do **not** share a uid: html->33, Postgres->70, edge/vpn/ops->root. Fixed in the script |
| **Drive unplugged while mounted = silent data loss** | The T5 was unplugged mid-session for a cable swap. fstab is `nofail` and nothing remounts on replug, so `/mnt/bulk` reverted to a plain root-fs directory and docker recreated the bind-mount sources there -- Nextcloud wrote 44 MB to the internal SSD. A later `mount -a` then **hid** it rather than moving it. Recovered by stashing, mounting, rsyncing back. `up.sh` now refuses to start cloud/media/download unless `/mnt/bulk` is a real mountpoint. Containers also keep the stale mount until recreated |
| gluetun + PIA: "VPN provider name is not valid for Wireguard" | gluetun speaks WireGuard to only some providers; **PIA is OpenVPN-only**, which is why `VPN_TYPE` lives in `.env`. PIA credentials are the account login (`p7905962`), not the separately-generated SOCKS pair |
| Sonarr/Radarr reject the qBittorrent client | "qBittorrent is configured to remove torrents when they reach their Share Ratio Limit" -- set `max_ratio_act` to **0 (pause)**, not 1 (remove), or the torrent vanishes before import |
| qBittorrent's port never matches PIA's | qBittorrent `depends_on` gluetun being healthy, so gluetun's up-command always fires before qBittorrent exists (exit 4) and the port silently disagrees. `scripts/qbt-port-sync.sh` on a 10-minute timer reconciles it |
| qBittorrent API login looks like it fails but does not | qBittorrent 5.x names the session cookie `QBT_SID_<port>`, not `SID` |
| Both *arr apps need `gluetun` as the download-client host | Not `qbittorrent` -- gluetun owns that network namespace, so the container name does not resolve |
| ddns-updater: "permission denied" on updates.json | It runs as uid 1000, so `/srv/apps/vpn/ddns` must be owned by 1000 |
| Kalshi bot: `open db  error="unable to open database file: out of memory (14)"` | Misleading message -- SQLite 14 is `CANTOPEN`, i.e. **permissions**. The image runs as **uid 10001 (`app`)**, so `data/` must be `chown 10001:10001`. `keys/` and `deploy/` want owner `hash` with **group 10001** and mode 750/640, so the container can read them while the shell user can still manage them (chmod 700 there locks out `kalshi.sh`'s own preflight) |
| Transferring the bot repo hangs for many minutes | The working tree carries gigabytes of untracked Parquet tick archives -- `du` on it times out. Do not tar the directory. `git archive --format=tar HEAD` emits only tracked files (1.1 MB) by construction, then `scp` the five git-ignored secret files separately. `deploy-kalshi.ps1` also pipes gzip through a PowerShell pipeline, which re-encodes bytes as text and corrupts the stream -- run the transfer from Git Bash instead |
| Plex link on the landing page fails with `PR_END_OF_FILE_ERROR` | **HSTS is scoped to the host, not the port.** After the browser sees `Strict-Transport-Security` for the domain it force-upgrades every `http://` URL on that host, including `:32400`, where Plex answers plain HTTP. Link Plex and Cockpit by **IP literal**, which the policy does not cover |
| Sonarr/Radarr cannot reach Plex: "Http request timed out" | Plex is `network_mode: host`; containers reach it from `172.28.x.x`, which neither the LAN nor WireGuard ufw rule covered. Fixed in `05-firewall.sh` |
| Kalshi dashboard always 401s; caddy logs `bcrypt: hashedSecret too short` | **Docker Compose v5 interpolates `env_file` values.** The bcrypt hash `$2a$14$Ryh...` had `$Ryh...` read as an undefined variable and blanked, leaving just `$2a$14$` (7 bytes). Double every `$` in `deploy/proxy.env` -> `$$2a$$14$$...`. The bot repo's README says env_file values are literal; that was true of older Compose. It fails by silently truncating a secret, not by erroring |
| Kalshi dashboard loads but every panel is empty, no error anywhere | The bot repo's `deploy/Caddyfile` had a bare `reverse_proxy @api` next to a catch-all `handle { }`. `handle` is a **terminal** handler and sorts BEFORE `reverse_proxy` in Caddy's default directive order, so the catch-all swallowed `/api/*` and `/ws/*` and served `index.html` (200, 536 bytes) for them. Fix: wrap it as `handle @api { reverse_proxy ... }` so both are handle blocks in source order. Symptom is invisible -- 200s with HTML bodies |
| Phone prompts for the dashboard login over and over | **Browsers cannot send Basic Auth on a WebSocket handshake** -- the WebSocket API has no header parameter, and iOS browsers do not reuse cached credentials for it. `/ws/live` 401s, the dashboard retries, every retry raises a new prompt. Fix: `@needsauth { not path /ws/live /ws/live/* /favicon.svg }` so the WS is exempt. `/api/*` stays protected, which is what matters -- the config-write endpoints live there. `/ws/live` is a read-only market-snapshot push, reachable only via LAN or the tunnel |
| Importing the local bot DB | Never copy `flipper.db` alone -- a 4 MB `-wal` sat beside it and would have been lost. Stop the bots, back up the server copy, `scp` **db + -wal + -shm together**, `chown 10001:10001`, then `pragma integrity_check` and `wal_checkpoint(TRUNCATE)` before restarting. Imported 56,773 opportunities and 2,085 orders this way |

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

## Media stack: evaluated a debrid rebuild, decided against it

The owner asked about switching to **Riven + Zilean + rclone + Plex** (debrid
streaming). After researching it the decision was to **stay local** -- keep
qBittorrent + PIA + Prowlarr/Sonarr/Radarr + Plex. Do not rebuild this without a
new explicit request.

What the goal actually was: *"add stuff to the wishlist on Plex and it just gets
downloaded and ready to watch."* That is now **done, with no new infrastructure** --
Radarr and Sonarr each have a native **Plex Watchlist import list** (`PlexImport` /
`PlexListSettings`, authenticated with the Plex account token from
`Preferences.xml`), syncing every **5 minutes**. Add to the watchlist, it is
searched, downloaded, hardlinked into the library, and Plex is notified.

Findings from the research, so nobody repeats it:

| Claim | Reality |
|---|---|
| Riven + TorBox | **Does not exist.** `src/program/services/downloaders/` has only `realdebrid.py`, `alldebrid.py`, `debridlink.py` |
| TorBox free tier has API access | **No** -- the API needs a paid plan. Third-party guides claiming otherwise are wrong |
| Riven needs rclone + zurg | **No longer.** Riven ships its own FUSE VFS (`RIVEN_FILESYSTEM_MOUNT_PATH`, own cache/chunking). zurg is Real-Debrid-only anyway |
| DMB (Debrid Media Bridge) | **Deprecated** Jan 2026, superseded by DUMB |
| TorBox with the *arr stack | Works via **Decypharr** (`cy01/blackhole`), which mocks the qBittorrent API and mounts via FUSE. Supports RD, TorBox, AllDebrid, Debrid-Link, Premiumize |
| Zilean | Usable by Prowlarr as a Torznab indexer, not just by Riven. First DMM ingest is heavy -- would want the 16 GB upgrade first |

If revisited later, the two coherent paths are **Real-Debrid + Riven** (biggest
cache, native watchlist polling, replaces the *arr apps) or **Real-Debrid +
Decypharr** (keeps the *arr apps, smaller change). Cache hit rate is what decides
whether playback is actually instant, and Real-Debrid's is materially larger than
TorBox's.

## Owner's stated preferences

Direct and brief. Answer the question asked, lead with the command or the code, skip
preamble, apologies and filler. No enthusiasm. If something is wrong, say so in a
sentence and keep going.
