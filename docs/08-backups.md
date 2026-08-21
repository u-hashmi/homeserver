# 08 — Backups

## What is worth backing up

| Tier | What | Where |
|---|---|---|
| 1 | Container configs, Postgres dump, `flipper.db`, Caddy certs, WireGuard peer keys, Nextcloud user files, `/etc` bits | restic repo on `/mnt/bulk/backups/restic`, plus optional offsite |
| 2 | Media library | **Not backed up.** A second 1 TB drive is not worth spending on re-downloadable content |

Nextcloud user files *are* tier 1 — those are the irreplaceable ones.

## Setup

```bash
# a strong passphrase, stored where root can read it and nobody else can
openssl rand -base64 48 | sudo tee /root/.restic-password >/dev/null
sudo chmod 600 /root/.restic-password
sudo ./scripts/backup.sh          # first run initialises the repo
```

**Write that passphrase down somewhere off the machine.** A restic repo without its
passphrase is random noise — there is no recovery path.

## Schedule it

```bash
sudo tee /etc/systemd/system/homeserver-backup.service >/dev/null <<'UNIT'
[Unit]
Description=homeserver backup
After=docker.service mnt-bulk.mount
Requires=mnt-bulk.mount

[Service]
Type=oneshot
ExecStart=/srv/homeserver/scripts/backup.sh
Nice=10
IOSchedulingClass=idle
UNIT

sudo tee /etc/systemd/system/homeserver-backup.timer >/dev/null <<'UNIT'
[Unit]
Description=nightly homeserver backup

[Timer]
OnCalendar=*-*-* 04:15:00
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now homeserver-backup.timer
systemctl list-timers homeserver-backup.timer
```

04:15 is chosen to sit outside trading hours and after Plex's scheduled tasks.
`IOSchedulingClass=idle` keeps it from making Plex stutter if you are watching
something.

## How the script avoids corrupt backups

- **Postgres** — `pg_dump`, never a file copy of `/srv/apps/cloud/db`. That directory
  is explicitly excluded; copying a live Postgres data dir gives you a backup that
  restores into corruption.
- **SQLite** — `sqlite3 .backup`, the only safe way to copy a WAL-mode database while
  it is being written.
- **Nextcloud** — flipped into maintenance mode for the duration of the file pass, so
  the database dump and the file tree describe the same moment.
- **Refuses to run** if `/mnt/bulk` is not mounted, instead of quietly writing a
  backup into the empty mountpoint on the root filesystem.

Retention: 7 daily, 5 weekly, 12 monthly, then `restic check --read-data-subset=2%`
so bit-rot surfaces on its own rather than the day you need a restore.

## Offsite

One drive in one building is one fire away from nothing. Backblaze B2 costs a few
dollars a month for this dataset:

```bash
sudo tee -a /etc/environment >/dev/null <<'ENV'
RESTIC_OFFSITE_REPOSITORY=b2:your-bucket-name:homeserver
B2_ACCOUNT_ID=...
B2_ACCOUNT_KEY=...
ENV
```

`backup.sh` picks up `RESTIC_OFFSITE_REPOSITORY` and `restic copy`s the local repo
up after each run — so the slow part happens once, locally, and the upload is
deduplicated.

## Restoring

```bash
export RESTIC_REPOSITORY=/mnt/bulk/backups/restic
export RESTIC_PASSWORD_FILE=/root/.restic-password

sudo restic snapshots
sudo restic ls latest /srv/apps                       # browse
sudo restic restore latest --target /tmp/restore --include /srv/apps/download/sonarr
```

### Nextcloud database

```bash
gunzip -c /tmp/restore/tmp/*/nextcloud.sql.gz \
  | docker exec -i nextcloud-db psql -U nextcloud -d nextcloud
docker exec -u www-data nextcloud php occ maintenance:mode --off
docker exec -u www-data nextcloud php occ files:scan --all
```

### Kalshi database

```bash
./scripts/kalshi.sh down
sudo cp /tmp/restore/tmp/*/flipper.db /srv/apps/kalshi/kalshi-flipper/data/flipper.db
sudo chown 10001:10001 /srv/apps/kalshi/kalshi-flipper/data/flipper.db
./scripts/kalshi.sh up
```

### Full rebuild from bare metal

The reason `/srv/homeserver` itself is in the backup: docs 01 through 03, then restore
`/srv/apps` and `/mnt/bulk/nextcloud-data`, then `./scripts/up.sh`. The stacks are
declarative — nothing is configured by hand on the host that these scripts do not set.

## Test a restore

Once, now, while nothing depends on it:

```bash
sudo restic restore latest --target /tmp/restore-test --include /srv/apps/edge
ls -R /tmp/restore-test && sudo rm -rf /tmp/restore-test
```

An untested backup is a guess.
