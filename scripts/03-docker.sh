#!/usr/bin/env bash
# Docker Engine + compose plugin from Docker's own apt repo, with log rotation and
# the shared `edge` network the reverse proxy and every web UI live on.
set -euo pipefail
[[ $EUID -eq 0 ]] && { echo "run as your normal user, not root"; exit 1; }

EDGE_SUBNET="${EDGE_SUBNET:-172.28.0.0/16}"

if ! command -v docker >/dev/null 2>&1; then
  echo "==> docker apt repo"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get -y install docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
fi

echo "==> daemon config: capped logs, live-restore, local storage driver"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'CFG'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "userland-proxy": false
}
CFG
sudo systemctl enable --now docker
sudo systemctl restart docker

echo "==> add $USER to the docker group"
sudo usermod -aG docker "$USER"

echo "==> shared 'edge' network ($EDGE_SUBNET)"
# Fixed subnet so gluetun's killswitch can be told to allow replies to the proxy.
if ! docker network inspect edge >/dev/null 2>&1; then
  sudo docker network create --driver bridge --subnet "$EDGE_SUBNET" edge
fi

echo "==> render-group id for QuickSync passthrough"
getent group render || echo "  (no render group — Plex compose falls back to /dev/dri perms)"
ls -l /dev/dri || echo "  !! no /dev/dri — check BIOS integrated graphics"

echo
echo "==> done. LOG OUT AND BACK IN so the docker group applies, then:"
echo "    docker run --rm hello-world"
