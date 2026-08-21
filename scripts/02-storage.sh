#!/usr/bin/env bash
# Format + permanently mount the 1 TB external USB3 drive at /mnt/bulk, then lay out
# the directory tree.
#
# Layout rule that matters:
#   INTERNAL SSD  →  /srv/apps/*   configs, Postgres, SQLite, Plex metadata
#   USB 1 TB      →  /mnt/bulk/*   media files, Nextcloud user files, backups
# Databases on a removable bus corrupt. Never move them to /mnt/bulk.
#
# Usage:  ./scripts/02-storage.sh /dev/sda        (wipes that disk, mounts, makes dirs)
#         ./scripts/02-storage.sh                 (skip formatting, just mount+dirs)
#         ./scripts/02-storage.sh --no-bulk        (SSD tree only, drive not attached yet)
set -euo pipefail
[[ $EUID -eq 0 ]] && { echo "run as your normal user, not root"; exit 1; }

DISK="${1:-}"
NO_BULK=0
[[ "$DISK" == "--no-bulk" ]] && { NO_BULK=1; DISK=""; }
MNT=/mnt/bulk
LABEL=bulk
UID_N="$(id -u)"; GID_N="$(id -g)"

if [[ -n "$DISK" ]]; then
  echo "!! about to ERASE $DISK:"
  lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,MOUNTPOINT "$DISK"
  read -rp "type the disk path again to confirm: " confirm
  [[ "$confirm" == "$DISK" ]] || { echo "mismatch, aborting"; exit 1; }

  sudo umount "${DISK}"* 2>/dev/null || true
  sudo wipefs -a "$DISK"
  sudo sgdisk -Z -n 1:0:0 -t 1:8300 -c 1:"$LABEL" "$DISK"
  sudo partprobe "$DISK"; sleep 2
  PART="$(lsblk -lno NAME "$DISK" | sed -n 2p)"
  # -m 1 : 1% reserved instead of 5% — that's 40 GB back on a 1 TB media drive.
  sudo mkfs.ext4 -m 1 -L "$LABEL" "/dev/$PART"
fi

if [[ $NO_BULK -eq 1 ]]; then
  echo "==> --no-bulk: skipping the 1 TB drive entirely."
  echo "    Creating the SSD tree only. Re-run without --no-bulk once the drive is in."
  echo "    Do NOT start the cloud/media/download stacks until then: with /mnt/bulk"
  echo "    unmounted, docker creates the bind-mount sources on the ROOT filesystem,"
  echo "    so your data silently lands on the 256 GB SSD."
else

echo "==> mount by UUID"
UUID="$(sudo blkid -s UUID -o value "$(sudo blkid -L "$LABEL")")"
[[ -n "$UUID" ]] || { echo "no filesystem labelled '$LABEL' found — pass the disk path to format it"; exit 1; }
sudo mkdir -p "$MNT"
FSTAB_LINE="UUID=$UUID  $MNT  ext4  defaults,noatime,nofail,x-systemd.device-timeout=15s  0  2"
if ! grep -q "$UUID" /etc/fstab; then
  echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
fi
sudo systemctl daemon-reload
sudo mount -a
findmnt "$MNT"

echo "==> stop USB autosuspend killing a 24/7 drive"
sudo tee /etc/udev/rules.d/50-usb-nosuspend.rules >/dev/null <<'CFG'
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
CFG
sudo udevadm control --reload-rules || true

fi   # end of bulk-drive section

echo "==> directory tree"
# Bulk: media laid out so *arr hardlinks work (one mount root, mounted as /data
# in every container — see TRaSH-guides hardlink docs).
if [[ $NO_BULK -eq 0 ]]; then
sudo mkdir -p \
  "$MNT"/media/downloads/{complete,incomplete} \
  "$MNT"/media/library/{tv,movies,music,audiobooks,podcasts} \
  "$MNT"/nextcloud-data \
  "$MNT"/backups
fi
# Internal SSD: everything stateful and latency-sensitive.
sudo mkdir -p \
  /srv/apps/{edge,vpn,cloud,media,download,ops} \
  /srv/apps/cloud/{db,redis,html} \
  /srv/apps/media/{plex,audiobookshelf} \
  /srv/apps/download/{gluetun,qbittorrent,prowlarr,sonarr,radarr,bazarr} \
  /srv/apps/ops/{uptime-kuma} \
  /srv/apps/edge/{caddy-data,caddy-config} \
  /srv/apps/kalshi

sudo chown -R "$UID_N:$GID_N" /srv/apps
if [[ $NO_BULK -eq 0 ]]; then
  sudo chown -R "$UID_N:$GID_N" "$MNT"/media "$MNT"/nextcloud-data
  sudo chmod -R 775 "$MNT"/media
  sudo chown -R root:root "$MNT"/backups
  sudo chmod 700 "$MNT"/backups
fi

echo
echo "==> done. PUID=$UID_N PGID=$GID_N  (put these in the stack .env files)"
if [[ $NO_BULK -eq 1 ]]; then
  df -h /
  echo
  echo "    SSD tree ready. Safe to bring up now: edge, vpn, ops, kalshi."
  echo "    Blocked until the drive is in: cloud, media, download."
else
  df -h / "$MNT"
fi
