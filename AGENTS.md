# AGENTS.md

Guidance for coding agents working in this repository.

## What This Repo Does

This repo manages self-hosted dynamic DNS and nginx-backed subdomain provisioning.

- Cloudflare is the primary path via `update-cloudflare-dyndns.sh`.
- Strato is the legacy path via `update-dyndns.sh`.
- Both updater scripts are installed as systemd oneshot services triggered by timers.
- `add-subdomain.sh` provisions Cloudflare CNAME records plus nginx HTTP or TCP proxy config.
- `www/` contains the static site served at the root domain.
- `docker-compose.yml` can run the static site with `nginx:alpine` for a simple local/container path.

## Important Files

- `.env`: Cloudflare credentials and runtime config. Do not commit real values.
- `.env.example`: Cloudflare config template.
- `cloudflare-dyndns.conf`: legacy Cloudflare config fallback. Do not commit real secrets.
- `strato-dyndns.conf`: Strato credentials. Do not commit real secrets.
- `update-cloudflare-dyndns.sh`: Cloudflare A/AAAA updater for the root domain.
- `update-dyndns.sh`: Strato DynDNS updater.
- `install-cloudflare.sh`: installs the Cloudflare updater, config, cache/log paths, and timer.
- `install.sh`: installs the Strato updater, config, cache/log paths, and timer.
- `add-subdomain.sh`: adds or removes Cloudflare CNAME records and nginx config.
- `madtec.nginx.conf`: nginx config for the root static site.
- `cloudflare-dyndns.service` / `cloudflare-dyndns.timer`: Cloudflare systemd units.
- `strato-dyndns.service` / `strato-dyndns.timer`: Strato systemd units.

## Setup And Deployment

Run install scripts from the repo root and as root:

```bash
sudo bash install-cloudflare.sh
sudo bash install.sh
```

Cloudflare install behavior:

- requires `jq` and installs it with `apt-get install -y jq` if missing
- copies `update-cloudflare-dyndns.sh` to `/usr/local/bin/update-cloudflare-dyndns.sh`
- copies repo `.env` to `/usr/local/bin/.env` when present
- falls back to copying `cloudflare-dyndns.conf` to `/usr/local/bin/cloudflare-dyndns.conf`
- creates `/var/cache/cloudflare-dyndns` and `/var/log/cloudflare-dyndns.log`
- installs and enables `cloudflare-dyndns.timer`
- starts `cloudflare-dyndns.service` once after installation

Strato install behavior:

- copies `update-dyndns.sh` to `/usr/local/bin/update-dyndns.sh`
- copies `strato-dyndns.conf` to `/usr/local/bin/strato-dyndns.conf`
- patches the installed script's `CONF_FILE` to point at `/usr/local/bin/strato-dyndns.conf`
- creates `/var/cache/strato-dyndns` and `/var/log/strato-dyndns.log`
- installs and enables `strato-dyndns.timer`
- starts `strato-dyndns.service` once after installation

## Runtime Config

Cloudflare config is loaded from the updater script directory:

1. `.env`
2. `cloudflare-dyndns.conf`

Required Cloudflare variables:

- `CF_TOKEN`
- `CF_ZONE_ID`
- `DOMAIN`
- `IFACE`

The legacy `cloudflare-dyndns.conf` path may also define `ZONE_ID`; the updater maps that to `CF_ZONE_ID` for compatibility.

Strato config is loaded from `strato-dyndns.conf` and should define:

- `DOMAIN`
- `HOSTNAME`
- `PASSWORD`
- `IFACE`

## Subdomain Management

Examples:

```bash
bash add-subdomain.sh app 3000
bash add-subdomain.sh db tcp:5432
bash add-subdomain.sh app 3000 --remove
```

Expected behavior:

- HTTP mode creates a Cloudflare CNAME from `<sub>.$DOMAIN` to `$DOMAIN`, writes `/etc/nginx/sites-available/<fqdn>`, symlinks it into `/etc/nginx/sites-enabled/`, validates nginx, and reloads nginx.
- TCP mode creates the same Cloudflare CNAME, writes `/etc/nginx/stream.conf.d/<fqdn>.conf`, validates nginx, and reloads nginx.
- Remove mode deletes the CNAME if present, removes both possible nginx config files, validates nginx, and reloads nginx.

Subdomain TLS assumes the wildcard certificate files exist at:

- `/etc/letsencrypt/live/${DOMAIN}/fullchain.pem`
- `/etc/letsencrypt/live/${DOMAIN}/privkey.pem`

## Runtime Behavior

Cloudflare updater flow:

1. Fetch public IPv4 with `curl -4 -s --max-time 10 https://api.ipify.org`.
2. Read the first global IPv6 on `$IFACE` that is not temporary, deprecated, tentative, dadfailed, or ULA (`fd*`/`fc*`).
3. Compare the combined IP string with `/var/cache/cloudflare-dyndns/last_ips`.
4. Skip Cloudflare API calls when IPs are unchanged.
5. Create or update root-domain A and AAAA records with TTL 60 and `proxied:false`.

Known failure mode: when `$IFACE` no longer matches an existing interface (e.g. a USB adapter was removed), step 2 silently returns empty, the cache stores a trailing-comma string like `79.199.x.x,`, and AAAA is never refreshed. The log line `IPs unchanged (79.199.x.x,), skipping` is the tell. Cross-check `grep '^IFACE=' /usr/local/bin/.env` against `ip -o link show` and `ip -6 -o addr show scope global`.

Strato updater flow:

1. Fetch public IPv4 with `curl -4 -s --max-time 10 https://api.ipify.org`.
2. Read the first global IPv6 on `$IFACE` that is not temporary or ULA (`fd*`/`fc*`).
3. Compare the combined IP string with `/var/cache/strato-dyndns/last_ips`.
4. Skip Strato calls when IPs are unchanged.
5. Send `hostname` and `myip` to Strato's DynDNS endpoint and cache only `good` or `nochg` responses.

## Monitoring

Useful commands:

```bash
systemctl list-timers cloudflare-dyndns.timer
journalctl -u cloudflare-dyndns.service -f
tail -f /var/log/cloudflare-dyndns.log

systemctl list-timers strato-dyndns.timer
journalctl -u strato-dyndns.service -f
tail -f /var/log/strato-dyndns.log
```

## Agent Rules

- Prefer minimal, targeted shell script and docs changes.
- Preserve secret-handling behavior and never commit credential values.
- Never echo `.env`, `cloudflare-dyndns.conf`, or `strato-dyndns.conf` to chat or stdout. The Cloudflare API token in there can edit DNS for the whole zone. Use `grep -v` / `sed` to redact when inspection is needed, or `source` the file inside a subshell so the values stay in process env and never appear in tool output.
- Do not replace the install flow with a different deployment model unless explicitly requested.
- Keep Cloudflare and Strato updater behavior aligned when changing shared IP detection or cache semantics.
- When editing systemd or nginx-related files, verify paths and service names against the existing scripts.
- Be careful with local changes: this repo may have untracked agent docs or edited scripts.
