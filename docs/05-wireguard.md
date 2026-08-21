# 05 — WireGuard: the only way in

One forwarded UDP port. Everything else on this box is unreachable from the internet,
which is why none of the web UIs below need to be internet-hardened.

## 1. Router

| Setting | Value |
|---|---|
| Static DHCP reservation | `192.168.1.50` → the M910q's MAC |
| Port forward | UDP **51820** → `192.168.1.50:51820` |
| UPnP | Off. You just did this by hand; leave it off |

Forward **only** UDP 51820. Not 80, not 443, not 32400.

## 2. Dynamic DNS

Home IPs rotate. `ddns-updater` keeps `vpn.<your-domain>` pointing at your current
public IP so client configs never need editing.

```bash
cp stacks/vpn/.env.example        stacks/vpn/.env
cp stacks/vpn/ddns-config.json.example /srv/apps/vpn/ddns/config.json
chmod 600 /srv/apps/vpn/ddns/config.json
```

Edit `config.json` with your Cloudflare zone ID and an API token scoped to
*Zone → DNS → Edit* on that zone only.

No domain? Use DuckDNS instead — `ddns-updater` supports it, and set
`WG_HOST=yourname.duckdns.org`.

## 3. DNS records

With the recommended setup (`stacks/edge/Caddyfile`, real certs) you need two
records, both **DNS-only / grey cloud, never proxied**:

| Name | Type | Value | Note |
|---|---|---|---|
| `*.home.example.com` | A | `192.168.1.50` | The **private** LAN IP. Resolves publicly, routes only inside the tunnel or on the LAN |
| `vpn.home.example.com` | A | managed by ddns-updater | Your public IP |

Publishing a private IP in public DNS looks odd but is deliberate and safe: it points
at an address nobody outside your network can route to. It's what lets Caddy get real
Let's Encrypt certificates via DNS-01 while nothing is exposed.

## 4. Bring it up

```bash
docker run --rm ghcr.io/wg-easy/wg-easy:14 wgpw 'YOUR_UI_PASSWORD'
# paste the hash into stacks/vpn/.env as WG_UI_PASSWORD_HASH
# IMPORTANT: double every $ in the hash ($$) — docker compose eats single ones
./scripts/up.sh vpn
```

UI: `https://wg.<domain>` via Caddy, or `http://192.168.1.50:51821` directly.

## 5. Clients

Add a peer per device in the UI, then scan the QR code (phone) or download the
`.conf` (laptop).

- **iPhone / Android** — official WireGuard app, scan the QR.
- **Windows** — WireGuard app, *Import tunnel from file*.
- **Linux** — `sudo cp peer.conf /etc/wireguard/home.conf && sudo wg-quick up home`

### Split tunnel is the default

`WG_ALLOWED_IPS` is set to `192.168.1.0/24,10.8.0.0/24`, so only traffic bound for
home goes through the tunnel. Netflix, work VPNs and your phone's battery all stay
normal, and you can leave the tunnel connected permanently — which is what makes
Plexamp and the Nextcloud app "just work".

Want everything routed (public Wi-Fi, geo-shifting)? Set
`WG_ALLOWED_IPS=0.0.0.0/0,::/0` and recreate the peers.

### MTU

`WG_MTU=1380` is set deliberately. The 1420 default breaks large transfers on some
mobile carriers and PPPoE links in a way that looks like "Nextcloud uploads hang at
99%". If you see that, drop it to 1280.

## 6. Verify

From your phone on cellular, tunnel up:

```
https://home.example.com          → the landing page
https://nextcloud.home.example.com
http://192.168.1.50:32400/web     → Plex
```

Then confirm the door is actually shut — from outside, tunnel **down**:

```bash
nmap -Pn -p 22,80,443,3389,9090,32400 your-public-ip     # expect all filtered
nmap -Pn -sU -p 51820 your-public-ip                     # expect open|filtered
```
