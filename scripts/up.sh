#!/usr/bin/env bash
# Bring stacks up (or restart / pull / show them). Each stack is independent; order
# only matters in that `edge` owns 80/443 and should exist before you test URLs.
#
#   ./up.sh                 all stacks, in order
#   ./up.sh cloud media     just those
#   ACTION=pull ./up.sh     pull new images everywhere (then re-run to apply)
#   ACTION=down ./up.sh     stop everything
#   ACTION=ps   ./up.sh     what's running
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${ACTION:-up}"
ALL=(edge vpn cloud media download ops)
STACKS=("$@")
[[ ${#STACKS[@]} -eq 0 ]] && STACKS=("${ALL[@]}")

docker network inspect edge >/dev/null 2>&1 || {
  echo "!! the 'edge' network is missing — run scripts/03-docker.sh first"; exit 1; }

for s in "${STACKS[@]}"; do
  dir="$ROOT/stacks/$s"
  [[ -d "$dir" ]] || { echo "-- no such stack: $s"; continue; }
  if [[ ! -f "$dir/.env" ]]; then
    echo "!! $s/.env missing. cp $dir/.env.example $dir/.env and fill it in."
    exit 1
  fi
  echo "==> $s: $ACTION"
  case "$ACTION" in
    up)   docker compose -f "$dir/docker-compose.yml" --project-directory "$dir" -p "$s" up -d --remove-orphans ;;
    down) docker compose -f "$dir/docker-compose.yml" --project-directory "$dir" -p "$s" down ;;
    pull) docker compose -f "$dir/docker-compose.yml" --project-directory "$dir" -p "$s" pull ;;
    ps)   docker compose -f "$dir/docker-compose.yml" --project-directory "$dir" -p "$s" ps ;;
    logs) docker compose -f "$dir/docker-compose.yml" --project-directory "$dir" -p "$s" logs --tail=50 ;;
    *)    docker compose -f "$dir/docker-compose.yml" --project-directory "$dir" -p "$s" "$ACTION" ;;
  esac
done

if [[ "$ACTION" == up ]]; then
  echo
  echo "==> containers:"
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
fi
