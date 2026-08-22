#!/usr/bin/env bash
# Push notifications to your phone for the things that otherwise fail silently.
#
# Delivery is ntfy (https://ntfy.sh) -- free, no account, proper iOS/Android apps.
# The topic name IS the credential: anyone who knows it can read your alerts and
# send you fake ones, so it lives in /etc/homeserver-alerts.conf (mode 600) and is
# never committed. Subscribe to that topic in the ntfy app.
#
# Only STATE CHANGES notify. A disk that has been over 80% for a week does not
# re-notify every 30 minutes; it alerts once when it crosses and once when it
# recovers. State is kept in /var/lib/homeserver-alerts.
#
# Run from a systemd timer -- see docs/09-operations.md.
set -uo pipefail

CONF=/etc/homeserver-alerts.conf
STATE_DIR=/var/lib/homeserver-alerts
DISK_WARN=${DISK_WARN:-80}
BULK=${BULK:-/mnt/bulk}

[[ -r "$CONF" ]] || { echo "missing $CONF (needs NTFY_TOPIC=...)"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
: "${NTFY_TOPIC:?NTFY_TOPIC not set in $CONF}"
NTFY_URL=${NTFY_URL:-https://ntfy.sh}

mkdir -p "$STATE_DIR"

# notify <key> <state> <priority> <tags> <title> <message>
# Sends only when <state> differs from the last recorded state for <key>.
notify() {
  local key=$1 state=$2 prio=$3 tags=$4 title=$5 msg=$6
  local f="$STATE_DIR/$key" prev=""
  [[ -f "$f" ]] && prev=$(cat "$f")
  [[ "$prev" == "$state" ]] && return 0
  printf '%s' "$state" > "$f"
  # Skip the very first run for healthy states, or you get a wall of "OK" on setup.
  [[ -z "$prev" && "$state" == "ok" ]] && return 0
  curl -fsS --max-time 15 \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: $tags" \
    -d "$msg" "$NTFY_URL/$NTFY_TOPIC" >/dev/null 2>&1 \
    && echo "notified: $key -> $state" \
    || echo "notify FAILED: $key -> $state"
}

# ---- disk ---------------------------------------------------------------------
check_disk() {
  local path=$1 label=$2 pct avail
  pct=$(df --output=pcent "$path" 2>/dev/null | tail -1 | tr -dc '0-9')
  avail=$(df -h --output=avail "$path" 2>/dev/null | tail -1 | tr -d ' ')
  [[ -n "$pct" ]] || return 0
  if (( pct >= DISK_WARN )); then
    notify "disk-$label" "warn" "high" "floppy_disk,warning" \
      "$label ${pct}% full" \
      "$label is at ${pct}% ($avail free). Threshold is ${DISK_WARN}%."$'\n'"Delete some media, or move the library to a bigger disk."
  else
    notify "disk-$label" "ok" "default" "floppy_disk,white_check_mark" \
      "$label back under ${DISK_WARN}%" "$label is at ${pct}% ($avail free)."
  fi
}

# ---- the bulk drive is actually mounted ---------------------------------------
# If it is not, docker writes to the root filesystem instead and the data is
# invisible once the drive returns. This has happened once already.
check_mount() {
  if mountpoint -q "$BULK"; then
    notify mount ok default "white_check_mark" "$BULK remounted" "The bulk drive is mounted again."
  else
    notify mount fail urgent "rotating_light" "$BULK IS NOT MOUNTED" \
      "Nextcloud and the media stacks will write to the internal SSD instead, and the data will be HIDDEN when the drive returns."$'\n'"Fix: sudo mount $BULK && ./scripts/up.sh cloud media download"
  fi
}

# ---- the VPN killswitch still holds ------------------------------------------
check_vpn() {
  docker inspect -f '{{.State.Running}}' qbittorrent 2>/dev/null | grep -q true || {
    notify vpn skip default "" "" "" ; return 0; }
  local host qbt
  host=$(curl -fsS4 --max-time 10 https://api.ipify.org 2>/dev/null)
  qbt=$(docker exec qbittorrent wget -qO- --timeout=10 https://api.ipify.org 2>/dev/null)
  if [[ -z "$qbt" ]]; then
    notify vpn down high "warning" "Torrent VPN is down" \
      "qBittorrent has no connectivity, so the killswitch is holding and nothing is downloading. Check: docker logs gluetun"
  elif [[ "$qbt" == "$host" ]]; then
    notify vpn leak urgent "rotating_light" "VPN LEAK" \
      "qBittorrent is using your real IP ($host). Stop the download stack now: ./scripts/up.sh down download"
  else
    notify vpn ok default "white_check_mark" "Torrent VPN healthy" "qBittorrent is on $qbt, host is $host."
  fi
}

# ---- containers that died ----------------------------------------------------
check_containers() {
  local dead
  dead=$(docker ps -a --filter 'status=exited' --filter 'label=com.docker.compose.project' \
           --format '{{.Names}}' 2>/dev/null | paste -sd, -)
  if [[ -n "$dead" ]]; then
    notify containers "dead:$dead" high "warning" "Container(s) stopped" "Exited: $dead"
  else
    notify containers ok default "white_check_mark" "All containers running" "Nothing exited."
  fi
}

# ---- backups are actually happening ------------------------------------------
check_backup() {
  local repo=${RESTIC_REPOSITORY:-$BULK/backups/restic}
  local pwfile=${RESTIC_PASSWORD_FILE:-/root/.restic-password}
  [[ -r "$pwfile" ]] || return 0
  local last age
  last=$(restic -r "$repo" --password-file "$pwfile" snapshots --json --latest 1 2>/dev/null \
          | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d[0]["time"][:19] if d else "")' 2>/dev/null)
  [[ -n "$last" ]] || { notify backup none high "warning" "No backup found" "restic has no snapshots in $repo."; return 0; }
  age=$(( ( $(date +%s) - $(date -d "$last" +%s) ) / 3600 ))
  if (( age > 48 )); then
    notify backup stale high "warning" "Backup is ${age}h old" \
      "Last restic snapshot: $last. The nightly timer may be failing -- systemctl status homeserver-backup"
  else
    notify backup ok default "white_check_mark" "Backups healthy" "Last snapshot $last (${age}h ago)."
  fi
}

case "${1:-run}" in
  test)
    curl -fsS --max-time 15 -H "Title: homeserver test" -H "Tags: white_check_mark" \
      -d "Alerts are wired up. You will get a message when a disk crosses ${DISK_WARN}%, the bulk drive unmounts, the torrent VPN leaks or drops, a container dies, or backups go stale." \
      "$NTFY_URL/$NTFY_TOPIC" >/dev/null && echo "test notification sent"
    ;;
  reset) rm -f "$STATE_DIR"/*; echo "state cleared"; ;;
  run)
    check_disk /      "Root disk"
    check_disk "$BULK" "Media drive"
    check_mount
    check_vpn
    check_containers
    check_backup
    ;;
  *) echo "usage: $0 [run|test|reset]"; exit 1 ;;
esac
