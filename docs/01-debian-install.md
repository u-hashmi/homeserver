# 01 — Install Debian 13 (trixie)

## Before you wipe

The 256 GB SSD is getting erased. Off the M910q first:
- Windows licence: it's an OEM digital licence tied to the board firmware. If you
  ever reinstall Windows it re-activates by itself — nothing to save.
- Anything in `C:\Users\...` you care about.

## Make the installer USB

On your Windows box:

1. Download the **netinst** image: <https://www.debian.org/download> (amd64).
2. Write it with [Rufus](https://rufus.ie) — target GPT/UEFI, mode "DD image" if it
   offers the choice.

## Install

Boot the USB (F12 for the boot menu). Choose **Graphical install**.

| Prompt | Answer |
|--------|--------|
| Hostname | `homeserver` |
| Domain name | leave blank (or `lan`) |
| Root password | leave **empty** — this makes your user a sudoer, which is what you want |
| User | your name, e.g. `hash` — this is uid 1000 and the docker/PUID user everywhere below |
| Partitioning | **Guided – use entire disk** → *all files in one partition* → the 256 GB SSD |
| Unplug the 1 TB during install | Yes. Removes any chance of installing onto the wrong disk |
| Swap | The guided scheme makes one. `01-base.sh` tunes it and adds zram later |
| Software selection | Check **only** `SSH server` + `standard system utilities`. Uncheck everything else, the desktop environment above all |

At the *Software selection* screen, the checkboxes should end up like this:

```
[ ] Debian desktop environment      uncheck  (and every sub-option under it)
[ ] GNOME / KDE / Xfce / LXDE ...   uncheck
[ ] web server                      uncheck  (Caddy runs in a container)
[ ] print server                    uncheck
[x] SSH server                      KEEP  - or you are stuck on a physical keyboard
[x] standard system utilities       KEEP  - curl, less, and other basics
```

> Do **not** install a desktop environment here. `04-remote-access.sh` installs a
> minimal XFCE for XRDP without the display manager and extra services a full
> desktop task pulls in.

## First boot

Missed a checkbox on the software selection screen? Both are recoverable:

```bash
sudo apt update
sudo tasksel install standard      # if you skipped "standard system utilities"
sudo apt install openssh-server    # if you skipped "SSH server"
systemctl is-active ssh
```

```bash
ip -4 addr show scope global        # confirm the IP matches your DHCP reservation
sudo apt update && sudo apt -y full-upgrade
sudo apt -y install git
```

Now pull this repo onto the box and continue with
[02-host-setup.md](02-host-setup.md):

```bash
sudo mkdir -p /srv && sudo chown $USER:$USER /srv
cd /srv && git clone <your-repo-url> homeserver     # or scp the folder over
cd /srv/homeserver && chmod +x scripts/*.sh
```

No repo yet? From Windows PowerShell in `D:\AI\HomeServer`:

```powershell
tar -czf - --exclude=.git . | ssh hash@192.168.1.50 "mkdir -p /srv/homeserver && tar -xzf - -C /srv/homeserver"
```
