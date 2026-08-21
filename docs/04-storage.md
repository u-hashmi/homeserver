# 04 — Storage

## The rule

| Lives on | What | Why |
|---|---|---|
| **Internal 256 GB SSD** — `/srv/apps/*` | Postgres, the bot's SQLite, Plex metadata db, all container configs, Caddy certs, WireGuard keys | Databases on a removable USB bus corrupt when the bus resets. Also: random-IO on spinning USB storage makes Plex browsing feel broken |
| **External 1 TB USB3** — `/mnt/bulk/*` | Media library, downloads, Nextcloud user files, restic backup repo | Sequential, large, replaceable |

Never move a database to `/mnt/bulk`, even temporarily.

## Run it

Find the disk (with the drive plugged in):

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,MOUNTPOINT
```

Then, with the correct device — **this erases it**:

```bash
./scripts/02-storage.sh /dev/sda
```

Re-running with no argument just re-mounts and re-creates any missing directories:

```bash
./scripts/02-storage.sh
```

## What it does

- GPT + a single ext4 partition labelled `bulk`, formatted with `-m 1` (1% reserved
  instead of ext4's default 5% — that's ~40 GB back on a 1 TB drive).
- Mounts by **UUID** in `/etc/fstab`, with `nofail,x-systemd.device-timeout=15s`:
  the machine still boots if the drive is unplugged, instead of dropping to an
  emergency shell you can only reach with a physical keyboard.
- A udev rule pinning `power/control=on` for USB devices, so the kernel doesn't
  autosuspend a drive that needs to stay awake 24/7.

## The tree

```
/mnt/bulk/
├── media/
│   ├── downloads/{complete,incomplete}     qBittorrent writes here
│   └── library/{tv,movies,music,audiobooks,podcasts}
│                                           *arr hardlinks here, Plex reads it
├── nextcloud-data/                         Nextcloud user files
└── backups/restic/                         restic repo (root-only, 0700)

/srv/apps/
├── edge/{caddy-data,caddy-config}
├── vpn/{wg-easy,ddns}
├── cloud/{db,html}
├── media/{plex,audiobookshelf}
├── download/{gluetun,qbittorrent,prowlarr,sonarr,radarr,bazarr}
├── ops/uptime-kuma
└── kalshi/kalshi-flipper/                  the bot repo + its data/ SQLite
```

## Why `media/` is one mount root

Every container in the download stack mounts `/mnt/bulk/media` as **`/data`** — not
`/downloads` and `/tv` as separate volumes. Docker treats each volume as its own
filesystem, so a "move" across two of them becomes a full copy: slow, and it doubles
disk use while seeding. One root means Sonarr and Radarr can hardlink an imported
file, so the seeding torrent and the Plex library entry are the same bytes on disk.

On a 1 TB drive that distinction is the difference between a working setup and a
full disk.

## Space budget on 1 TB

| | |
|---|---|
| Nextcloud files | plan 100–200 GB |
| Audiobooks + music | 50–100 GB |
| restic backups | 30–80 GB (config + Nextcloud files, deduplicated) |
| Media library + active torrents | whatever's left, ~600 GB |

Set a Sonarr/Radarr retention policy early. `ncdu /mnt/bulk` when you want to know
where it went.
