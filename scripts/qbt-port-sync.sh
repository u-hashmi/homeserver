#!/usr/bin/env bash
# Reconcile qBittorrent's listening port with the port PIA has forwarded.
#
# Why this exists: gluetun runs VPN_PORT_FORWARDING_UP_COMMAND the moment it obtains
# a port, but qBittorrent `depends_on` gluetun being *healthy*, so on a cold start
# qBittorrent does not exist yet and that command always fails with exit 4. The
# up-command only helps on a mid-session renewal. This closes the loop from the
# other side: compare the two and push the port in whenever they disagree.
#
# Requires "Bypass authentication for clients on localhost" in the qBittorrent WebUI,
# which is set. Run from a systemd timer -- see docs/06-services.md.
set -euo pipefail

docker inspect -f '{{.State.Running}}' gluetun 2>/dev/null | grep -q true || exit 0
docker inspect -f '{{.State.Running}}' qbittorrent 2>/dev/null | grep -q true || exit 0

PORT="$(docker exec gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null || true)"
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "no forwarded port yet"; exit 0; }

qc() { docker run --rm --network container:gluetun curlimages/curl:latest -s \
         -H 'Referer: http://127.0.0.1:8080' "$@"; }

CUR="$(qc http://127.0.0.1:8080/api/v2/app/preferences \
        | grep -oE '"listen_port":[0-9]+' | cut -d: -f2 || true)"

if [[ "$CUR" == "$PORT" ]]; then
  echo "listen_port already $PORT"
  exit 0
fi

qc -X POST http://127.0.0.1:8080/api/v2/app/setPreferences \
   --data-urlencode "json={\"listen_port\":$PORT,\"random_port\":false,\"upnp\":false}" >/dev/null

NEW="$(qc http://127.0.0.1:8080/api/v2/app/preferences \
        | grep -oE '"listen_port":[0-9]+' | cut -d: -f2 || true)"
if [[ "$NEW" == "$PORT" ]]; then
  echo "listen_port: ${CUR:-unset} -> $PORT"
  command -v logger >/dev/null && logger -t qbt-port-sync "listen_port ${CUR:-unset} -> $PORT"
else
  echo "!! failed to set listen_port (wanted $PORT, got ${NEW:-unset})"
  exit 1
fi
