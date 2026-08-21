# 02 — Host setup

Run these in order from `/srv/homeserver`. All three are idempotent.

```bash
./scripts/01-base.sh        # packages, zram + swap, log caps, auto security patches
./scripts/03-docker.sh      # docker engine + compose + the shared `edge` network
# --- LOG OUT AND BACK IN so the docker group takes effect ---
docker run --rm hello-world
```

Firewall last, once you know your subnet:

```bash
ip -4 route | grep default          # confirm your LAN subnet
LAN=192.168.1.0/24 ./scripts/05-firewall.sh
```

## What `01-base.sh` sets and why

| Setting | Value | Reason |
|---|---|---|
| zram | zstd, 50% of RAM, priority 100 | Compressed swap in RAM. On an 8 GB box this is the single cheapest way to survive a Plex transcode plus Nextcloud PHP workers |
| `/swapfile` | 4 GB, priority 10 | Second-tier fallback once zram is full, so the OOM killer doesn't take out `bot-live` |
| `vm.swappiness` | 20 | Low enough to keep hot pages resident, high enough to actually use zram |
| `fs.inotify.max_user_watches` | 524288 | Sonarr, Radarr, Nextcloud and Plex all watch large trees; the default 8192 silently breaks file monitoring |
| `net.ipv4.ip_forward` | 1 | WireGuard has to route between the tunnel and the LAN |
| journald | capped at 500 MB | 256 GB SSD, 24/7 uptime |
| sleep targets | masked | A server that suspends is a server you can't reach |
| unattended-upgrades | security pocket only | Patches land automatically; kernel reboots stay your decision |

## What `03-docker.sh` sets

- Docker from Docker's own apt repo, not Debian's (compose v2 plugin, current engine).
- `log-opts max-size=10m max-file=3` — without this, one chatty container fills the SSD.
- `live-restore: true` — containers keep running through a `dockerd` restart.
- An external bridge network called **`edge`** on a fixed subnet (`172.28.0.0/16`).
  Every stack attaches to it, and Caddy reaches services by container name. The subnet
  is pinned because gluetun's killswitch needs to be told that range is allowed —
  a floating subnet would break the download stack every time Docker renumbered.

## Verify QuickSync is visible

```bash
ls -l /dev/dri            # expect card0 + renderD128
vainfo | head -20         # expect "VAEntrypointEncSlice" lines for H264 and HEVC
```

No `/dev/dri`? Integrated graphics is disabled in BIOS, or a discrete card is
selected as primary.
