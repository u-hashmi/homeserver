#!/usr/bin/env bash
# Monthly-ish maintenance. Deliberately manual: unattended container updates are how
# a working media server becomes a broken one at 3am. Debian *security* patches do
# install automatically (see 01-base.sh); this is for everything else.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> backup first"
sudo "$ROOT/scripts/backup.sh"

echo "==> host packages"
sudo apt-get update && sudo apt-get -y full-upgrade && sudo apt-get -y autoremove --purge

echo "==> container images"
# Nextcloud is excluded on purpose: it must be upgraded ONE major at a time, with
# the tag bumped by hand in stacks/cloud/.env. Pulling it blind can skip a major
# and leave the instance refusing to start.
ACTION=pull "$ROOT/scripts/up.sh" edge vpn media download ops
ACTION=up   "$ROOT/scripts/up.sh" edge vpn media download ops

echo "==> kalshi bots (rebuild from source)"
"$ROOT/scripts/kalshi.sh" up || echo "   (skipped — repo not present)"

echo "==> reclaim disk"
docker image prune -af --filter 'until=168h'
docker builder prune -af --filter 'until=168h'

echo "==> reboot needed?"
if [[ -f /var/run/reboot-required ]]; then
  echo "   YES — kernel or libc updated. sudo reboot when convenient."
  cat /var/run/reboot-required.pkgs 2>/dev/null || true
else
  echo "   no"
fi

df -h / /mnt/bulk
free -h
