#!/usr/bin/env bash
# Create/update the two Cloudflare DNS records this build needs, via the API, so
# there is no clicking in the dashboard and no typo in an IP.
#
#   *.home.coder-geist.com   A -> the server's PRIVATE LAN IP   (services)
#   home.coder-geist.com     A -> the server's PRIVATE LAN IP   (landing page)
#   vpn.coder-geist.com      A -> the current PUBLIC IP          (WireGuard endpoint)
#
# Both service records are DNS-only (never proxied): Cloudflare must not sit in front
# of a private address, and Caddy needs the real name to resolve for its own checks.
#
# Publishing a private IP in public DNS is deliberate. It points at an address nobody
# outside your network can route to, and it is what lets Caddy hold a real wildcard
# certificate while nothing is exposed.
#
# Usage:
#   CF_DNS_API_TOKEN=... ./scripts/cf-dns.sh home.coder-geist.com 192.168.1.50
set -euo pipefail

DOMAIN="${1:?usage: cf-dns.sh <services-domain> <lan-ip>}"
LAN_IP="${2:?usage: cf-dns.sh <services-domain> <lan-ip>}"
: "${CF_DNS_API_TOKEN:?set CF_DNS_API_TOKEN}"

# Registered zone = last two labels of the services domain.
ZONE="$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')"
VPN_NAME="vpn.$ZONE"
API=https://api.cloudflare.com/client/v4
auth=(-H "Authorization: Bearer $CF_DNS_API_TOKEN" -H "Content-Type: application/json")

api() { curl -fsS "${auth[@]}" "$@"; }
try() { curl -sS "${auth[@]}" "$@" 2>/dev/null; }   # non-fatal: no -f, survives 401

# Cloudflare has two token kinds with two different verify endpoints. User-owned
# tokens verify at /user/tokens/verify; ACCOUNT-owned tokens 401 there and must
# use /accounts/<id>/tokens/verify. Try both, and treat neither working as a
# warning rather than fatal -- the zone lookup below is what actually matters.
echo "==> verifying the token"
verified=0
try "$API/user/tokens/verify" | grep -q '"status":"active"' && { verified=1; echo "    user-owned token, active"; }
if [[ $verified -eq 0 && -n "${CF_ACCOUNT_ID:-}" ]]; then
  try "$API/accounts/$CF_ACCOUNT_ID/tokens/verify" | grep -q '"status":"active"' \
    && { verified=1; echo "    account-owned token, active"; }
fi
[[ $verified -eq 1 ]] || echo "    note: neither verify endpoint confirmed it; continuing"

echo "==> looking up zone $ZONE"
ZONE_ID="$(api "$API/zones?name=$ZONE" | sed -n 's/.*"result":\[{"id":"\([a-f0-9]*\)".*/\1/p')"
[[ -n "$ZONE_ID" ]] || { echo "!! zone $ZONE not found, or the token lacks Zone:Read on it"; exit 1; }
echo "    zone id $ZONE_ID"

upsert() {
  local name="$1" content="$2" comment="$3"
  local id
  id="$(api "$API/zones/$ZONE_ID/dns_records?type=A&name=$name" \
        | sed -n 's/.*"result":\[{"id":"\([a-f0-9]*\)".*/\1/p')"
  local body
  body="$(printf '{"type":"A","name":"%s","content":"%s","ttl":300,"proxied":false,"comment":"%s"}' \
          "$name" "$content" "$comment")"
  if [[ -n "$id" ]]; then
    api -X PATCH "$API/zones/$ZONE_ID/dns_records/$id" --data "$body" >/dev/null
    echo "    updated  $name -> $content"
  else
    api -X POST "$API/zones/$ZONE_ID/dns_records" --data "$body" >/dev/null
    echo "    created  $name -> $content"
  fi
}

echo "==> service records (private LAN IP, DNS-only)"
upsert "$DOMAIN"   "$LAN_IP" "homeserver services (LAN only)"
upsert "*.$DOMAIN" "$LAN_IP" "homeserver services wildcard (LAN only)"

echo "==> wireguard endpoint (public IP)"
PUBLIC_IP="$(curl -fsS4 https://api.ipify.org)"
echo "    current public ip: $PUBLIC_IP"
upsert "$VPN_NAME" "$PUBLIC_IP" "wireguard endpoint - kept current by ddns-updater"

echo
echo "==> done. verify propagation (TTL 300s):"
echo "    dig +short nextcloud.$DOMAIN   # expect $LAN_IP"
echo "    dig +short $VPN_NAME           # expect $PUBLIC_IP"
