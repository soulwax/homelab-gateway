# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Does

Self-hosted dynamic DNS with nginx-backed subdomain provisioning.

- **Cloudflare** (`update-cloudflare-dyndns.sh`): primary path. Uses the Cloudflare API to create or update root-domain A and AAAA records.
- **Strato** (`update-dyndns.sh`): legacy path. Uses Strato's HTTP DynDNS protocol with basic auth.
- **Subdomains** (`add-subdomain.sh`): creates/removes Cloudflare CNAME records and nginx HTTP or TCP proxy config.
- **Static site** (`www/`): root-domain static content. `madtec.nginx.conf` is the nginx vhost, and `docker-compose.yml` can serve `www/` with `nginx:alpine`.

Both DynDNS providers run as systemd oneshot services triggered by 15-minute persistent timers.

## Credentials And Config

Do not commit real secrets.

- `.env`: current Cloudflare config. Required variables are `CF_TOKEN`, `CF_ZONE_ID`, `DOMAIN`, and `IFACE`. `.env.example` documents the expected shape.
- `cloudflare-dyndns.conf`: legacy Cloudflare fallback loaded only when `.env` is absent beside the updater script. The updater also maps legacy `ZONE_ID` to `CF_ZONE_ID`.
- `strato-dyndns.conf`: Strato config. Expected variables are `DOMAIN`, `HOSTNAME`, `PASSWORD`, and `IFACE`.

Cloudflare config is loaded from the updater script directory, so installed config lives at `/usr/local/bin/.env` or `/usr/local/bin/cloudflare-dyndns.conf`.

## Install And Deploy

Run from the repo directory as root:

```bash
# Cloudflare primary path
sudo bash install-cloudflare.sh

# Strato legacy path
sudo bash install.sh
```

`install-cloudflare.sh`:

- installs `jq` with `apt-get install -y jq` if missing
- copies `update-cloudflare-dyndns.sh` to `/usr/local/bin/`
- copies `.env` to `/usr/local/bin/.env`, or falls back to `cloudflare-dyndns.conf`
- creates `/var/cache/cloudflare-dyndns` and `/var/log/cloudflare-dyndns.log`
- installs/enables `cloudflare-dyndns.timer`
- starts `cloudflare-dyndns.service` once

`install.sh`:

- copies `update-dyndns.sh` to `/usr/local/bin/`
- copies `strato-dyndns.conf` to `/usr/local/bin/`
- patches the installed `CONF_FILE` path with `sed`
- creates `/var/cache/strato-dyndns` and `/var/log/strato-dyndns.log`
- installs/enables `strato-dyndns.timer`
- starts `strato-dyndns.service` once

## Subdomain Management

```bash
# HTTP reverse proxy
bash add-subdomain.sh <sub> <port>

# TCP stream proxy
bash add-subdomain.sh <sub> tcp:<port>

# Remove
bash add-subdomain.sh <sub> <port> --remove
```

HTTP mode writes `/etc/nginx/sites-available/<fqdn>`, symlinks it into `/etc/nginx/sites-enabled/`, validates nginx, and reloads nginx.

TCP mode writes `/etc/nginx/stream.conf.d/<fqdn>.conf`, validates nginx, and reloads nginx. The nginx installation must include/load stream config snippets from that directory.

TLS for HTTP subdomains assumes wildcard certificate files at `/etc/letsencrypt/live/${DOMAIN}/fullchain.pem` and `/etc/letsencrypt/live/${DOMAIN}/privkey.pem`.

## IP Detection Logic

Cloudflare:

1. IPv4: `curl -4 -s --max-time 10 https://api.ipify.org`.
2. IPv6: first global address on `$IFACE` that is not temporary, deprecated, tentative, dadfailed, or ULA.
3. Cache: `/var/cache/cloudflare-dyndns/last_ips`.
4. DNS: upsert root-domain A and AAAA records with TTL 60 and `proxied:false`.

Strato:

1. IPv4: `curl -4 -s --max-time 10 https://api.ipify.org`.
2. IPv6: first global address on `$IFACE` that is not temporary or ULA.
3. Cache: `/var/cache/strato-dyndns/last_ips`.
4. DNS: call Strato DynDNS and cache only `good` or `nochg` responses.

## Monitoring

```bash
systemctl list-timers cloudflare-dyndns.timer
journalctl -u cloudflare-dyndns.service -f
tail -f /var/log/cloudflare-dyndns.log

systemctl list-timers strato-dyndns.timer
journalctl -u strato-dyndns.service -f
tail -f /var/log/strato-dyndns.log
```

## Working Rules

- Prefer minimal, targeted shell script changes.
- Preserve current secret handling.
- Keep the existing systemd and nginx deployment model unless explicitly asked to change it.
- Verify concrete paths and service names against the scripts before documenting or editing them.
