#!/usr/bin/env bash
# Host baseline: packages, swap/zram tuning, log rotation, unattended security
# upgrades, timezone. Idempotent — re-run any time.
set -euo pipefail
[[ $EUID -eq 0 ]] && { echo "run as your normal user, not root (it sudos itself)"; exit 1; }

TZ_NAME="${TZ_NAME:-America/New_York}"

echo "==> packages"
sudo apt-get update
sudo apt-get -y install \
  ca-certificates curl gnupg git jq tree htop iotop ncdu tmux rsync unzip \
  smartmontools lm-sensors nvme-cli \
  ufw fail2ban unattended-upgrades apt-listchanges \
  zram-tools restic \
  intel-gpu-tools vainfo

# QuickSync verification driver. Lives in Debian's non-free component, which is not
# enabled by default -- and it only makes `vainfo` on the HOST report codecs
# accurately. The Plex container ships its own VAAPI drivers, so hardware
# transcoding does not depend on this. Best-effort on purpose: a missing candidate
# must never abort the rest of this script.
if sudo apt-get -y install intel-media-va-driver-non-free 2>/dev/null; then
  echo '    quicksync verification driver installed'
else
  cat <<'NOTE'
    note: intel-media-va-driver-non-free has no candidate (non-free not enabled).
          Optional -- Plex transcoding works without it. To enable non-free:
            sudo sed -i 's/^Components: .*/Components: main contrib non-free non-free-firmware/' \
              /etc/apt/sources.list.d/debian.sources
            sudo apt update && sudo apt install intel-media-va-driver-non-free
NOTE
fi

echo "==> timezone + ntp"
sudo timedatectl set-timezone "$TZ_NAME"
sudo timedatectl set-ntp true

echo "==> zram (compressed RAM swap — cheap headroom on 8 GB)"
sudo tee /etc/default/zramswap >/dev/null <<'CFG'
ALGO=zstd
PERCENT=50
PRIORITY=100
CFG
sudo systemctl enable --now zramswap.service

echo "==> 4G disk swapfile as the second-tier fallback"
if ! swapon --show=NAME --noheadings | grep -q '/swapfile'; then
  if [[ ! -f /swapfile ]]; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
  fi
  sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw,pri=10 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

echo "==> sysctl"
sudo tee /etc/sysctl.d/99-homeserver.conf >/dev/null <<'CFG'
# Prefer reclaiming page cache over swapping; zram makes swap cheap but not free.
vm.swappiness = 20
vm.vfs_cache_pressure = 50
# Plex / Nextcloud / *arr all watch a lot of files.
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
# WireGuard forwards between the tunnel and the LAN.
net.ipv4.ip_forward = 1
CFG
sudo sysctl --system >/dev/null

echo "==> journald cap (256 GB SSD, no runaway logs)"
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/99-size.conf >/dev/null <<'CFG'
[Journal]
SystemMaxUse=500M
SystemMaxFileSize=50M
CFG
sudo systemctl restart systemd-journald

echo "==> unattended security upgrades"
sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'CFG'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CFG
# Security patches auto-install. Kernel reboots stay manual (see 09-operations.md).
sudo sed -i 's|^//\s*"origin=Debian,codename=${distro_codename}-security"|        "origin=Debian,codename=${distro_codename}-security"|' \
  /etc/apt/apt.conf.d/50unattended-upgrades || true

echo "==> never sleep; this is a server"
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo "==> smart monitoring"
# The real unit is smartmontools.service; smartd.service is a symlink alias, and
# systemd refuses to 'enable' a linked name. The package already enables it on
# install, so this is belt-and-braces.
sudo systemctl enable --now smartmontools.service || true
sudo sensors-detect --auto >/dev/null 2>&1 || true

echo "==> done. free -h:"
free -h
