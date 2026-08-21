# 09 — Running it

## Daily driving

```bash
./scripts/up.sh                      # start/refresh everything
ACTION=ps   ./scripts/up.sh          # what's running
ACTION=logs ./scripts/up.sh cloud    # last 50 lines of a stack
docker stats --no-stream             # live CPU/RAM per container
./scripts/kalshi.sh logs             # follow the bots
```

Or from a browser: Dozzle for logs, Cockpit for the host, Uptime Kuma for health.

## Updates

```bash
sudo ./scripts/update.sh
```

Backs up first, updates host packages, pulls new container images, rebuilds the bots,
prunes old images, and tells you whether a reboot is pending.

Container updates are deliberately **manual**. Unattended image pulls are how a
working media server becomes a broken one at 3am. Debian *security* patches do install
themselves — that trade-off goes the other way, since an unpatched sshd is worse than
an unexpected restart.

**Nextcloud is excluded from the bulk pull** and must be bumped one major at a time in
`stacks/cloud/.env`. Skipping a major leaves it refusing to start.

## RAM budget

Measured-ish, idle, on 8 GB:

| | |
|---|---|
| Debian + docker + xrdp (nobody connected) | ~450 MB |
| Caddy + ddns + wg-easy | ~90 MB |
| Nextcloud + Postgres + Redis + cron | ~700 MB |
| Plex (idle) | ~400 MB |
| Audiobookshelf | ~200 MB |
| gluetun + qBittorrent + Prowlarr + Sonarr + Radarr | ~800 MB |
| Bazarr | ~250 MB |
| Kalshi bots + their Caddy | ~150 MB |
| Uptime Kuma + Dozzle | ~140 MB |
| **Total** | **~3.2 GB** |

That leaves ~4.5 GB for page cache and transcodes, which is workable — until a Plex
transcode (up to ~1 GB) lands at the same time as Nextcloud PHP workers spinning up
for a large sync. That is the moment zram earns its keep, and the reason 16 GB is
worth $30.

If you need to shed weight, in order: `ops` stack, Bazarr, Audiobookshelf.

```bash
free -h
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}'
zramctl                                   # compression ratio actually achieved
```

## Disk

```bash
df -h / /mnt/bulk
sudo ncdu /srv/apps                       # SSD hogs — usually Plex metadata
sudo ncdu /mnt/bulk/media
docker system df                          # image/build cache
sudo smartctl -a /dev/nvme0n1 | grep -iE 'percentage used|media errors'
```

The SSD's two growth areas are Plex metadata and Docker build cache. `update.sh`
prunes the latter. If `/` gets tight, Plex's *Optimize database* and *Clean bundles*
tasks reclaim real space.

## Troubleshooting

**A web UI 502s through Caddy.** The container is down or renamed. `docker ps`, then
`docker logs caddy` — it names the upstream it could not reach. Caddy resolves
upstreams per-request, so it starts fine even when a backend does not exist; the 502
is the symptom, not the cause.

**Certificates fail to issue.** `docker logs caddy`. Almost always the Cloudflare
token: it needs *Zone → DNS → Edit* on that specific zone, and the record must be
DNS-only (grey cloud), not proxied.

**WireGuard connects but nothing loads.** Check `WG_ALLOWED_IPS` includes your actual
LAN subnet, and that `net.ipv4.ip_forward=1` survived (`sysctl net.ipv4.ip_forward`).
If large transfers hang at 99% but small ones work, it is MTU — drop `WG_MTU` to 1280.

**Downloads stall at 0 peers.** The port forward did not land.

```bash
docker logs gluetun | grep -i 'port forward'
docker exec gluetun sh -c 'wget -qO- https://ipinfo.io/ip'
```

Then confirm qBittorrent's listening port matches, and that *Bypass authentication for
clients on localhost* is enabled so gluetun's up-command can set it.

**Plex transcodes on the CPU instead of the GPU.** Needs Plex Pass, `/dev/dri` present
in the container (`docker exec plex ls -l /dev/dri`), and hardware acceleration ticked
in Settings → Transcoder.

**The 1 TB drive vanished.** `dmesg | tail -40` — usually a USB bus reset or the
enclosure sleeping.

```bash
sudo mount -a && findmnt /mnt/bulk
ACTION=up ./scripts/up.sh media download
```

Containers hold stale mounts after the drive returns, so restart the stacks that use
it. If this happens repeatedly, the enclosure or cable is the problem — that is the
argument for the internal 2.5" bay.

**XRDP shows a black screen or drops.** `sudo systemctl restart xrdp`. Only one
session per user; a stale one blocks the next.

**Everything is slow and `free -h` shows swap in use.** Something ballooned. `docker
stats` finds it. Usual suspects: a Plex library scan, Nextcloud preview generation, or
Bazarr.

## Health check to run monthly

```bash
timedatectl status | grep -E 'synchronized|NTP'    # the bot depends on this
sudo restic -r /mnt/bulk/backups/restic snapshots --latest 3
sudo ufw status verbose
docker exec qbittorrent sh -c 'wget -qO- https://ipinfo.io/ip'   # VPN still up?
curl -s ifconfig.me                                              # must differ
sudo smartctl -H /dev/nvme0n1
docker ps --filter 'status=exited'                               # anything died?
```

## Power and reboots

- BIOS *After Power Loss → Power On* means an outage self-heals.
- `restart: unless-stopped` on everything, Docker enabled at boot.
- Sleep targets are masked, so nothing suspends.
- A small UPS (even 350 VA) turns a brownout from a hard power cut into a clean
  ride-through — worth it mainly because the bot and Postgres are writing.
- Wake-on-LAN is enabled in BIOS: `wakeonlan <mac>` from another machine on the LAN.

## Adding a service later

1. New directory under `stacks/`, or a service in an existing compose file.
2. Attach it to the `edge` network.
3. One block in `stacks/edge/Caddyfile`, then `docker restart caddy`.
4. One line in `stacks/edge/site/index.html` if you want it on the landing page.

No ports to forward, no DNS to add — the wildcard record and the tunnel already cover
it.
