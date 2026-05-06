# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Self-hosted dynamic DNS with subdomain provisioning. Two providers are supported:

- **Cloudflare** (`update-cloudflare-dyndns.sh`): primary path for `madtec.org`. Uses the Cloudflare API to upsert A + AAAA records. Credentials come from `.env`.
- **Strato** (`update-dyndns.sh`): legacy path for `darkfloor.de`. Uses Strato's HTTP DynDNS protocol (basic auth). Credentials come from `strato-dyndns.conf`.

Both run as systemd **oneshot** services triggered by timers (every 15 min, persistent across reboots).

## Credentials and secrets

- `.env` — Cloudflare credentials (`CF_TOKEN`, `CF_ZONE_ID`, `DOMAIN`, `IFACE`). Never commit this file.
- `strato-dyndns.conf` — Strato credentials (`DOMAIN`, `HOSTNAME`, `PASSWORD`, `IFACE`). Never commit this file.
- `cloudflare-dyndns.conf` — legacy Cloudflare conf used by the install script path; superseded by `.env` in the current scripts.

## Install / deploy

All scripts require root. Run from the repo directory:

```bash
# Cloudflare (primary)
sudo bash install-cloudflare.sh

# Strato (legacy)
sudo bash install.sh
```

The install scripts copy scripts to `/usr/local/bin/`, patch the `CONF_FILE` path inside them via `sed`, create cache/log dirs, and enable the systemd timer.

## Subdomain management

```bash
# HTTP reverse proxy (creates Cloudflare CNAME + nginx site + reloads nginx)
bash add-subdomain.sh <sub> <port>

# TCP stream proxy
bash add-subdomain.sh <sub> tcp:<port>

# Remove
bash add-subdomain.sh <sub> <port> --remove
```

Nginx configs land in `/etc/nginx/sites-available/<fqdn>` (HTTP) or `/etc/nginx/stream.conf.d/<fqdn>.conf` (TCP). SSL uses the wildcard cert at `/etc/letsencrypt/live/${DOMAIN}/`.

## IP detection logic

Both updater scripts follow the same pattern:
1. IPv4: `curl -4 https://api.ipify.org` (external lookup, needed because the server is behind NAT).
2. IPv6: `ip -6 addr show dev $IFACE scope global`, filtering out `temporary` and ULA (`fd*/fc*`) addresses.
3. Cache at `/var/cache/*/last_ips` — skip the API call if IPs haven't changed.

## Monitoring

```bash
systemctl list-timers cloudflare-dyndns.timer
journalctl -u cloudflare-dyndns.service -f
tail -f /var/log/cloudflare-dyndns.log
```

## Static site

`www/` is served at the root domain. `madtec.nginx.conf` is the nginx vhost config for the root domain (copy to `/etc/nginx/sites-available/` and symlink to `sites-enabled/`). Alternatively, `docker-compose.yml` runs `nginx:alpine` serving `www/` on port 80.
