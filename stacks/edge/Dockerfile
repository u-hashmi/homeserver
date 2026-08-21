# Caddy plus the Cloudflare DNS module, so we can get real Let's Encrypt certs over a
# DNS-01 challenge with ZERO inbound ports open. The official image has no DNS
# providers compiled in, hence the xcaddy build.
FROM caddy:2-builder-alpine AS build
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy
