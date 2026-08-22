#!/usr/bin/env bash
# Force Radarr/Sonarr to actually re-read the Plex Watchlist.
#
# Why this exists: both Plex list types report minRefreshInterval = 06:00:00, and
# Radarr/Sonarr silently skip the upstream fetch inside that window no matter how
# often ImportListSync runs. So a title added to your watchlist can sit unnoticed
# for up to six hours. The RSS variant is NOT faster -- it carries the same 6 h
# interval, so switching list types does not help.
#
# Deleting and re-adding the list clears its stored refresh timestamp, which is the
# only lever that forces a real fetch. Radarr/Sonarr de-duplicate by TMDB/TVDB id,
# so re-adding never creates duplicate entries; only the list's own id and
# listOrder change, which is cosmetic.
#
# Run from a systemd timer -- see docs/06-services.md.
set -uo pipefail

log() { echo "$(date '+%F %T') $*"; }

refresh() {
  local app=$1 port=$2 cfgdir=$3
  local key url tmp body id http

  key=$(grep -oP '(?<=<ApiKey>)[^<]+' "$cfgdir/config.xml" 2>/dev/null) || return 0
  [[ -n "$key" ]] || { log "$app: no api key"; return 0; }
  url="http://$app:$port/api/v3/importlist"

  api() { docker run --rm --network edge curlimages/curl:latest -s -H "X-Api-Key: $key" "$@"; }

  # Grab the Plex Watchlist list verbatim so we can put it back unchanged.
  tmp=$(mktemp) || return 0
  api "$url" > "$tmp"
  body=$(python3 - "$tmp" <<'PY'
import json, sys
try:
    for l in json.load(open(sys.argv[1])):
        if l.get("implementation") in ("PlexImport", "PlexRssImport"):
            i = l.pop("id", None)
            print(i); print(json.dumps(l))
            break
except Exception:
    pass
PY
)
  rm -f "$tmp"
  id=$(printf '%s' "$body" | sed -n 1p)
  [[ -n "$id" ]] || { log "$app: no Plex Watchlist list configured, skipping"; return 0; }
  printf '%s' "$body" | sed -n 2p > /tmp/wl-$app.json

  api -X DELETE "$url/$id" -o /dev/null
  http=$(docker run --rm --network edge -v "/tmp/wl-$app.json:/l.json" curlimages/curl:latest -s \
          -X POST -H "X-Api-Key: $key" -H "Content-Type: application/json" --data @/l.json \
          -o /dev/null -w '%{http_code}' "$url?forceSave=true")
  rm -f "/tmp/wl-$app.json"

  if [[ "$http" != "201" && "$http" != "200" ]]; then
    log "$app: recreate returned HTTP $http -- list may be missing, check the UI"
    return 1
  fi

  api -X POST -H "Content-Type: application/json" --data '{"name":"ImportListSync"}' \
      "http://$app:$port/api/v3/command" -o /dev/null
  log "$app: watchlist list recreated (was id $id) and sync triggered"
}

refresh radarr 7878 /srv/apps/download/radarr
refresh sonarr 8989 /srv/apps/download/sonarr
