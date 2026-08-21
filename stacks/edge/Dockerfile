# Caddy plus the DNS provider modules. The official image compiles in none of them,
# so DNS-01 challenges need a custom build. Both providers are included so switching
# between Cloudflare and DuckDNS is a one-line .env change, not a rebuild.
FROM caddy:2-builder-alpine AS build
RUN xcaddy build \
      --with github.com/caddy-dns/cloudflare \
      --with github.com/caddy-dns/duckdns

FROM caddy:2-alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy
