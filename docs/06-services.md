# 06 — Services

Every stack: copy `.env.example` → `.env`, fill it in, then bring it up.

```bash
for s in edge vpn cloud media download ops; do
  cp -n stacks/$s/.env.example stacks/$s/.env
done
$EDITOR stacks/*/.env
./scripts/up.sh              # or ./scripts/up.sh cloud media
```

`./scripts/up.sh` refuses to start a stack whose `.env` is missing, rather than
starting it with silent defaults.

---

## edge — Caddy

The single HTTPS front door. Builds a custom Caddy with the Cloudflare DNS module
(the official image ships no DNS providers).

```bash
cp stacks/edge/.env.example stacks/edge/.env
# DOMAIN, ACME_EMAIL, CF_DNS_API_TOKEN
./scripts/up.sh edge
docker logs -f caddy          # watch the first cert issuance
```

Two TLS modes, chosen with `CADDYFILE` in `.env`:

- **`Caddyfile`** (recommended) — Let's Encrypt over a Cloudflare DNS-01 challenge.
  Real certs on every device with zero open ports. Needs a domain on Cloudflare and
  an API token scoped to *Zone → DNS → Edit*.
- **`Caddyfile.internal`** — Caddy's own CA. No domain needed. Install
  `/srv/apps/edge/caddy-data/caddy/pki/authorities/local/root.crt` on each device
  (Windows: `certlm.msc` → Trusted Root; iOS: install profile, then
  Settings → General → About → Certificate Trust Settings). Set `DOMAIN=home.arpa`
  and add hosts-file entries — see the comment block at the top of the file.

Adding a service later = one block in the Caddyfile + `docker restart caddy`.

---

## cloud — Nextcloud

```bash
cp stacks/cloud/.env.example stacks/cloud/.env
# POSTGRES_PASSWORD, NEXTCLOUD_ADMIN_*, DOMAIN
./scripts/up.sh cloud
```

First start takes 2–5 minutes to install. Then `https://nextcloud.<domain>`.

### Post-install, in this order

1. **Notes** — Apps → search "Notes" → Enable. That is the server side of Nextcloud
   Notes. Then install the Notes app on iOS/Android and point it at your Nextcloud
   account. Notes are plain Markdown files in `/Notes`, so they are also just files
   in the Files app and sync to your desktop.
2. **Also worth enabling** — Calendar, Contacts, Tasks, Deck.
3. **Clear the setup warnings** (Administration → Overview). Two need a shell:

   ```bash
   docker exec -u www-data nextcloud php occ db:add-missing-indices
   docker exec -u www-data nextcloud php occ maintenance:repair --include-expensive
   ```

4. **Phone/desktop sync** — the mobile app takes the URL plus a generated app
   password (Settings → Security → Create new app password). Works over WireGuard.

### Notes on the config

- App code, config and Postgres live on the SSD; user files on `/mnt/bulk`, via
  `NEXTCLOUD_DATA_DIR=/var/www/data`.
- `TRUSTED_PROXIES` plus `APACHE_DISABLE_REWRITE_IP=1` are what make Nextcloud see
  the real client IP through Caddy, instead of logging every login from `172.28.0.x`.
- `PHP_UPLOAD_LIMIT=16G`, and Caddy applies no body limit, so large uploads work.
- Postgres is tuned small on purpose (`shared_buffers=256MB`). Do not raise it on 8 GB.
- **Upgrades: one major at a time.** Bump `NEXTCLOUD_TAG` from `31-apache` to
  `32-apache`, `up -d`, wait for it to finish, then consider the next. Skipping a
  major leaves the instance refusing to start.

---

## media — Plex, Plexamp, Prologue, Audiobookshelf

```bash
# grab a claim token first — valid 4 minutes
# https://plex.tv/claim   ->   PLEX_CLAIM=claim-xxxxx in stacks/media/.env
./scripts/up.sh media
```

Plex: `http://192.168.1.50:32400/web`

### Why Plex is not behind Caddy

It runs on the **host network** and is not proxied. Two reasons: client discovery
needs broadcast traffic that a bridge network drops, and Plex already terminates its
own valid TLS on `:32400` through `*.plex.direct`. Proxying it breaks Plexamp
discovery and gains nothing.

### Plex settings to change

| Setting | Value | Why |
|---|---|---|
| Remote Access | **Disabled** | You reach it over WireGuard. Do not punch a hole |
| Network → Custom server access URLs | `http://192.168.1.50:32400` | So Plexamp and Prologue find it over the tunnel |
| Network → LAN Networks | `192.168.1.0/24,10.8.0.0/24` | Marks tunnel clients as local, so Plex direct-plays instead of transcoding |
| Transcoder → Hardware acceleration | On | Needs **Plex Pass**. Without it the i5-6500T manages about one 1080p stream in software |
| Transcoder → temporary directory | `/transcode` | Already mapped to `/dev/shm` — transcodes in RAM, saving SSD writes |
| Library → Scheduled tasks | 3–5am | Keeps thumbnail generation away from trading hours |

Verify hardware transcoding is actually happening — start a transcode, then:

```bash
docker exec plex intel_gpu_top          # the Video engine should show activity
```

### Libraries

| Library | Type | Path in container |
|---|---|---|
| Movies | Movies | `/data/library/movies` |
| TV | TV Shows | `/data/library/tv` |
| Music | Music | `/data/library/music` |
| Audiobooks | Music, agent set for audiobooks | `/data/library/audiobooks` |

**Plexamp** — free app, points at the Music library. Over WireGuard it connects
directly. Offline sync and a few extras need Plex Pass.

**Prologue** — iOS audiobook player that reads a Plex *Music* library. Set the
Audiobooks library's agent and scanner for audiobooks, and organise files as
`Author/Book Title/01 - Chapter.m4b`. Prologue then handles chapters, playback speed
and the sleep timer far better than Plex's own client.

**Audiobookshelf** (`https://books.<domain>`) is also running. It is a better
audiobook server than Plex — real progress sync, its own apps, podcast support. Both
read the same `audiobooks` folder, so use whichever you prefer. If you settle on
Prologue plus Plex, delete the `audiobookshelf` service to reclaim about 200 MB.

---

## download — VPN killswitch

```bash
cp stacks/download/.env.example stacks/download/.env
# VPN_SERVICE_PROVIDER + WIREGUARD_PRIVATE_KEY
./scripts/up.sh download

# to include Bazarr as well (skip it if you stay on 8 GB RAM):
docker compose -f stacks/download/docker-compose.yml \
  --project-directory stacks/download -p download --profile full up -d
```

### The killswitch is structural

qBittorrent and Prowlarr use `network_mode: "service:gluetun"` — they have no network
stack of their own. If the tunnel drops, they lose all connectivity. That cannot fail
silently the way a firewall rule or a "bind to interface" checkbox can.

Confirm it before you download anything:

```bash
docker exec gluetun     sh -c 'wget -qO- https://ipinfo.io/ip'   # the VPN's IP
docker exec qbittorrent sh -c 'wget -qO- https://ipinfo.io/ip'   # must be IDENTICAL
curl -s ifconfig.me                                              # your real IP — must DIFFER
```

If the second and third match, stop and fix it before going further.

### Provider choice

You need one that still does **port forwarding**, or you will be upload-only and
downloads will crawl. As of now that means ProtonVPN (NAT-PMP) or AirVPN — Mullvad
dropped it. gluetun supports both natively.

For ProtonVPN: account → WireGuard configuration → create a key with NAT-PMP
enabled → copy its `PrivateKey` line into `WIREGUARD_PRIVATE_KEY`.

`VPN_PORT_FORWARDING_UP_COMMAND` pushes the forwarded port straight into
qBittorrent. For that to work, enable **Bypass authentication for clients on
localhost** in qBittorrent → Options → Web UI.

### qBittorrent settings

`https://qbt.<domain>`. Default login is `admin` with a password printed to the log:

```bash
docker logs qbittorrent | grep -i password
```

Change it immediately, then:

| Setting | Value |
|---|---|
| Downloads → Default Save Path | `/data/downloads/complete` |
| Downloads → Incomplete path | `/data/downloads/incomplete` |
| Connection → Use UPnP/NAT-PMP | **Off** — gluetun owns the port |
| BitTorrent → Encryption | Require encryption |
| Advanced → Network interface | leave default; you are already inside the tunnel |

### *arr wiring

| App | URL | Points at |
|---|---|---|
| Prowlarr | `https://prowlarr.<domain>` | add indexers, then Settings → Apps → add Sonarr and Radarr |
| Sonarr | `https://sonarr.<domain>` | Download client: qBittorrent, host **`gluetun`**, port **8080** |
| Radarr | `https://radarr.<domain>` | same |
| Bazarr | `https://bazarr.<domain>` | Sonarr at `sonarr:8989`, Radarr at `radarr:7878` |

Root folders: `/data/library/tv` for Sonarr, `/data/library/movies` for Radarr.

Sonarr and Radarr reach qBittorrent at `gluetun:8080` because gluetun owns that
network namespace — **not** at `qbittorrent:8080`, which will not resolve.

Check hardlinks work after the first import. If the library file and the torrent file
are separate copies, you will fill the drive at double speed:

```bash
stat -c '%h %n' /mnt/bulk/media/library/tv/*/*/*.mkv | head   # link count should be 2
```

### About Tor

You mentioned Tor, so to be explicit: it is not in this build, deliberately.
WireGuard already gives you private remote access, and torrenting over Tor is both
unusably slow and actively harmful to a network volunteers run for people who need
it. The commercial VPN above is the right tool for the download path. If you want a
`.onion` for something else later, it is an independent container and touches none of
this.

---

## ops — optional

```bash
./scripts/up.sh ops
```

- **Uptime Kuma** (`https://status.<domain>`) — HTTP monitors per service plus push
  notifications. Worth adding a monitor on the bot's API and on a gluetun IP check,
  so you hear about a VPN drop instead of discovering it later.
- **Dozzle** (`https://logs.<domain>`) — live log tail for every container in a
  browser, over a read-only docker socket.

Combined about 140 MB. First thing to drop if you stay on 8 GB RAM.
