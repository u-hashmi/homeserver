#!/usr/bin/env bash
# Build + run the Kalshi-Flipper stack with the home-server overrides applied.
#
#   ./kalshi.sh          build & (re)start
#   ./kalshi.sh logs     follow both bots
#   ./kalshi.sh down     stop
#   ./kalshi.sh restart  restart bot-live only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${KALSHI_REPO:-/srv/apps/kalshi/kalshi-flipper}"
OVERRIDE="$ROOT/stacks/kalshi/docker-compose.override.yml"

[[ -d "$REPO" ]] || { echo "!! bot repo not at $REPO — see docs/07-kalshi-bot.md"; exit 1; }
for f in keys/.env deploy/live.env deploy/paper.env deploy/proxy.env; do
  [[ -f "$REPO/$f" ]] || { echo "!! missing $REPO/$f (secrets are not in git)"; exit 1; }
done

dc() { docker compose -f "$REPO/docker-compose.yml" -f "$OVERRIDE" \
        --project-directory "$REPO" -p kalshi "$@"; }

case "${1:-up}" in
  up)      dc up -d --build --remove-orphans; dc ps ;;
  down)    dc down ;;
  logs)    dc logs -f --tail=100 bot-live bot-paper ;;
  restart) dc restart "${2:-bot-live}" ;;
  *)       dc "$@" ;;
esac
