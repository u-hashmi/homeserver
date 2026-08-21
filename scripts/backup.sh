#!/usr/bin/env bash
# Nightly backup. Two tiers:
#
#   tier 1  everything small and irreplaceable — configs, Postgres dump, the bot's
#           SQLite, Caddy's certs, WireGuard peer keys, Plex metadata.
#           -> restic repo on /mnt/bulk/backups, and optionally offsite.
#   tier 2  media files. NOT backed up: 1 TB of re-downloadable content isn't worth
#           a second 1 TB drive. Nextcloud user files ARE in tier 1.
#
# Databases are dumped, never copied live. Copying a running Postgres data dir or a
# WAL-mode SQLite file gives you a backup that restores into corruption.
set -euo pipefail

BULK="${BULK:-/mnt/bulk}"
STAGE="$(mktemp -d)"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-$BULK/backups/restic}"
: "${RESTIC_PASSWORD_FILE:=/root/.restic-password}"
export RESTIC_PASSWORD_FILE
trap 'rm -rf "$STAGE"' EXIT

[[ $EUID -eq 0 ]] || { echo "run with sudo (needs to read /srv/apps and /root)"; exit 1; }
[[ -f "$RESTIC_PASSWORD_FILE" ]] || { echo "!! no $RESTIC_PASSWORD_FILE — see docs/08-backups.md"; exit 1; }
mountpoint -q "$BULK" || { echo "!! $BULK is not mounted, refusing to back up"; exit 1; }

restic snapshots >/dev/null 2>&1 || restic init

echo "==> postgres dump (Nextcloud)"
if docker ps --format '{{.Names}}' | grep -qx nextcloud-db; then
  docker exec -e PGPASSWORD -t nextcloud-db \
    sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
    > "$STAGE/nextcloud.sql"
  gzip -9 "$STAGE/nextcloud.sql"
else
  echo "   (nextcloud-db not running, skipping)"
fi

echo "==> sqlite snapshot (kalshi-flipper)"
KALSHI_DB="${KALSHI_DB:-/srv/apps/kalshi/kalshi-flipper/data/flipper.db}"
if [[ -f "$KALSHI_DB" ]]; then
  # .backup is the only safe way to copy a live WAL database.
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$KALSHI_DB" ".backup '$STAGE/flipper.db'"
  else
    docker run --rm -v "$(dirname "$KALSHI_DB")":/db -v "$STAGE":/out alpine \
      sh -c 'apk add -q sqlite && sqlite3 /db/'"$(basename "$KALSHI_DB")"' ".backup /out/flipper.db"'
  fi
fi

echo "==> nextcloud into maintenance mode for a consistent file snapshot"
NC_MAINT=0
if docker ps --format '{{.Names}}' | grep -qx nextcloud; then
  docker exec -u www-data nextcloud php occ maintenance:mode --on >/dev/null && NC_MAINT=1
fi

echo "==> restic backup"
restic backup \
  --tag homeserver \
  --exclude-caches \
  --exclude '/srv/apps/media/plex/Library/Application Support/Plex Media Server/Cache' \
  --exclude '/srv/apps/media/plex/Library/Application Support/Plex Media Server/Metadata' \
  --exclude '/srv/apps/cloud/db' \
  --exclude '*/appdata_*/preview' \
  "$STAGE" \
  /srv/homeserver \
  /srv/apps \
  "$BULK/nextcloud-data" \
  /etc/fstab /etc/docker /etc/ufw /etc/xrdp

[[ $NC_MAINT -eq 1 ]] && docker exec -u www-data nextcloud php occ maintenance:mode --off >/dev/null

echo "==> prune"
restic forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --tag homeserver
restic check --read-data-subset=2%

echo "==> offsite (optional; set RESTIC_OFFSITE_REPOSITORY to enable)"
if [[ -n "${RESTIC_OFFSITE_REPOSITORY:-}" ]]; then
  restic -r "$RESTIC_OFFSITE_REPOSITORY" copy --from-repo "$RESTIC_REPOSITORY" || \
    restic -r "$RESTIC_OFFSITE_REPOSITORY" init && \
    restic -r "$RESTIC_OFFSITE_REPOSITORY" copy --from-repo "$RESTIC_REPOSITORY"
fi

echo "==> done"
restic snapshots --latest 3
