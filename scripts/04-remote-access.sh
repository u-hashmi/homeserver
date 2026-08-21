#!/usr/bin/env bash
# Three ways in, all LAN/WireGuard-only:
#   sshd    :22    — hardened, key-only
#   xrdp    :3389  — XFCE desktop, works with Windows mstsc.exe and Linux Remmina
#   cockpit :9090  — browser server admin (updates, services, logs, terminal, SMART)
set -euo pipefail
[[ $EUID -eq 0 ]] && { echo "run as your normal user, not root"; exit 1; }

echo "==> xrdp + a minimal XFCE (no display manager, no desktop task bloat)"
sudo apt-get update
sudo apt-get -y install --no-install-recommends \
  xrdp xorgxrdp \
  xfce4 xfce4-terminal xfce4-goodies \
  dbus-x11 x11-xserver-utils \
  polkitd pkexec \
  firefox-esr thunar file-roller
# Not installed on purpose: lightdm/gdm (xrdp starts its own X session), pulseaudio,
# printing, network-manager applets. Keeps idle RAM near zero when nobody is logged in.

echo "==> tell xrdp sessions to start XFCE"
echo "xfce4-session" | sudo tee /etc/skel/.xsession >/dev/null
echo "xfce4-session" > "$HOME/.xsession"
sudo chown "$USER:$USER" "$HOME/.xsession"

echo "==> xrdp needs to read the TLS key"
sudo adduser xrdp ssl-cert >/dev/null 2>&1 || true

echo "==> xrdp tuning: 3389, TLS, sane colour depth for a WAN-over-WireGuard link"
sudo sed -i \
  -e 's/^port=.*/port=3389/' \
  -e 's/^security_layer=.*/security_layer=negotiate/' \
  -e 's/^crypt_level=.*/crypt_level=high/' \
  -e 's/^max_bpp=.*/max_bpp=24/' \
  -e 's/^#\?tcp_nodelay=.*/tcp_nodelay=true/' \
  -e 's/^#\?tcp_keepalive=.*/tcp_keepalive=true/' \
  /etc/xrdp/xrdp.ini

# Suppress the "authentication is required to create a color managed device" popups
# that block a fresh XFCE-over-RDP session. Debian 13 ships polkit >= 121, which
# dropped .pkla local authority files — this is the JS rules.d equivalent.
sudo mkdir -p /etc/polkit-1/rules.d
sudo tee /etc/polkit-1/rules.d/45-allow-colord.rules >/dev/null <<'CFG'
polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.color-manager.") === 0 && subject.local && subject.active) {
    return polkit.Result.YES;
  }
});
CFG

sudo systemctl enable --now xrdp xrdp-sesman
sudo systemctl restart xrdp

echo "==> cockpit (web admin: updates, services, logs, SMART, browser terminal)"
sudo apt-get -y install --no-install-recommends cockpit cockpit-storaged cockpit-networkmanager
sudo systemctl enable --now cockpit.socket

echo "==> ssh hardening (key-only). Make sure your key is installed FIRST:"
echo "    from your laptop:  ssh-copy-id $USER@$(hostname -I | awk '{print $1}')"
if [[ -s "$HOME/.ssh/authorized_keys" ]]; then
  sudo tee /etc/ssh/sshd_config.d/99-homeserver.conf >/dev/null <<'CFG'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 60
CFG
  sudo systemctl restart ssh
  echo "    ssh is now key-only."
else
  echo "    !! no authorized_keys found — leaving password auth ON."
  echo "       install your key, then re-run this script."
fi

echo "==> fail2ban for sshd"
sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null <<'CFG'
[sshd]
enabled = true
maxretry = 4
bantime = 1h
CFG
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban

cat <<MSG

==> done.

  Remote desktop from Windows:   mstsc.exe  →  192.168.1.50:3389
  Remote desktop from Linux:     remmina / xfreerdp /v:192.168.1.50 /dynamic-resolution
  Web admin:                     https://192.168.1.50:9090   (self-signed warning is expected)
  Shell:                         ssh $USER@192.168.1.50

  XRDP login = your Linux username + password (not your SSH key). Set/confirm it:
    passwd

  Only ONE session at a time per user. If a session hangs, from ssh:
    sudo systemctl restart xrdp
MSG
