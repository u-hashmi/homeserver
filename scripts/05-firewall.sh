#!/usr/bin/env bash
# ufw: deny inbound by default. Admin + web UIs are reachable only from the LAN and
# from the WireGuard subnet. The only rule that is open to the whole internet is the
# WireGuard UDP port — and that's the only port you forward on the router.
#
# Docker note: docker's iptables rules bypass ufw's INPUT chain for *published*
# ports. That is why nothing in these stacks publishes to 0.0.0.0 except Caddy
# (80/443), Plex (32400) and wg-easy (51820/udp) — all of which we want reachable on
# the LAN anyway. Everything else talks over the `edge` docker network only.
set -euo pipefail
[[ $EUID -eq 0 ]] && { echo "run as your normal user, not root"; exit 1; }

LAN="${LAN:-192.168.1.0/24}"
WG="${WG:-10.8.0.0/24}"
WG_PORT="${WG_PORT:-51820}"

echo "==> LAN=$LAN  WG=$WG  wireguard port=$WG_PORT"
read -rp "correct? [y/N] " ok; [[ "$ok" == y || "$ok" == Y ]] || exit 1

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default allow routed        # WireGuard clients need to reach the LAN

# From the internet: WireGuard only.
sudo ufw allow "$WG_PORT"/udp comment 'wireguard'

for src in "$LAN" "$WG"; do
  sudo ufw allow from "$src" to any port 22    proto tcp comment 'ssh'
  sudo ufw allow from "$src" to any port 3389  proto tcp comment 'xrdp'
  sudo ufw allow from "$src" to any port 9090  proto tcp comment 'cockpit'
  sudo ufw allow from "$src" to any port 80    proto tcp comment 'caddy http'
  sudo ufw allow from "$src" to any port 443   proto tcp comment 'caddy https'
  sudo ufw allow from "$src" to any port 51821 proto tcp comment 'wg-easy ui'
  sudo ufw allow from "$src" to any port 32400 proto tcp comment 'plex'
done

# Plex LAN discovery (only useful on the LAN itself, never routed).
sudo ufw allow from "$LAN" to any port 32410,32412,32413,32414 proto udp comment 'plex discovery'
sudo ufw allow from "$LAN" to any port 1900 proto udp comment 'plex dlna/ssdp'

# mDNS, so homeserver.local resolves on the LAN and you never have to hunt for
# the IP after a DHCP lease changes.
sudo ufw allow from "$LAN" to any port 5353 proto udp comment 'mdns'

sudo ufw logging low
sudo ufw --force enable
sudo ufw status verbose
