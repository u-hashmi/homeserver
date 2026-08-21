# 03 — Getting into the box

Three doors, all closed to the internet. Everything below is reachable on the LAN
directly, or from anywhere once the WireGuard tunnel is up ([05](05-wireguard.md)).

## Install

Put your SSH key on first, or the script leaves password auth enabled:

```bash
# from your laptop
ssh-copy-id hash@192.168.1.50
```

```bash
# on the server
./scripts/04-remote-access.sh
passwd            # confirm/set your Linux password — XRDP uses this, not your key
```

## SSH — `:22`

Key-only after the script runs. `PermitRootLogin no`, `PasswordAuthentication no`,
3 auth tries, fail2ban with a 1 hour ban.

```bash
ssh hash@192.168.1.50
```

Handy `~/.ssh/config` entry on your laptop:

```
Host home
    HostName 192.168.1.50
    User hash
    ServerAliveInterval 30
```

## Remote desktop — `:3389`

XRDP with a minimal XFCE session. **From Windows**, the built-in client:

```powershell
mstsc.exe /v:192.168.1.50 /f          # or just run mstsc and type the IP
```

**From Linux:**

```bash
xfreerdp3 /v:192.168.1.50 /u:hash /dynamic-resolution /clipboard +fonts
# or use Remmina / GNOME Connections and pick RDP
```

Notes that save an hour of confusion:

- Log in with your **Linux username + password**. RDP cannot use your SSH key.
- One session per user. Reconnecting resumes the same desktop; that's `xrdp-sesman`
  doing its job. If it hangs, `ssh` in and `sudo systemctl restart xrdp`.
- No display manager is installed, so nothing renders on a physically attached
  monitor — that's intentional (it saves ~400 MB idle). The console is text-only.
- Sound is not forwarded. Add `pulseaudio-module-xrdp` if you ever want it.
- Idle RAM cost is ~0 when nobody is connected; ~350–500 MB during a session.

## Web admin — `:9090`

Cockpit: system updates, service start/stop, journal search, SMART health, disk
usage, network config, and a browser terminal.

```
https://192.168.1.50:9090
```

Self-signed cert warning is expected — it's a LAN-only service on a port Caddy
doesn't front. Log in with your Linux user.

## Docker, from your laptop

Skip XRDP for container work — point your local Docker CLI at the server over SSH:

```powershell
docker context create home --docker "host=ssh://hash@192.168.1.50"
docker context use home
docker ps
```

VS Code's Remote-SSH extension works the same way and is the nicest way to edit
compose files and read logs.
