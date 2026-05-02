# madtec.org — DynDNS + Subdomain Manager

Self-hosted dynamic DNS with automatic subdomain provisioning via Cloudflare and nginx on Ubuntu 24.04.

## Setup

### 1. Configure credentials

Copy the example and fill in your values:

```bash
cp .env.example .env
```

```ini
# .env
CF_TOKEN="your-cloudflare-api-token"   # Zone:DNS:Edit permission
CF_ZONE_ID="your-zone-id"              # Cloudflare dashboard → domain overview → right sidebar
DOMAIN="madtec.org"
IFACE="wlxec750c68b7ce"                # interface with your public IPv6 (ip addr show)
```

### 2. Install the DynDNS timer

```bash
sudo bash install-cloudflare.sh
```

This copies the scripts to `/usr/local/bin/`, creates cache/log dirs, and enables a systemd timer that updates DNS every 15 minutes.

### 3. Wildcard SSL cert (one-time)

```bash
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare/madtec.ini \
  -d madtec.org -d '*.madtec.org'
```

---

## Add a subdomain

```bash
# HTTP reverse proxy  →  https://app.madtec.org  proxies to localhost:3000
bash add-subdomain.sh app 3000

# TCP passthrough  →  db.madtec.org:5432  routes to localhost:5432
bash add-subdomain.sh db tcp:5432

# Remove
bash add-subdomain.sh app 3000 --remove
```

Each call: creates a Cloudflare CNAME, writes an nginx config, reloads nginx.

---

## File overview

| File | Purpose |
|---|---|
| `.env` | Credentials — **never commit** |
| `update-cloudflare-dyndns.sh` | Updates A + AAAA records when IP changes |
| `add-subdomain.sh` | Provisions/removes subdomains |
| `cloudflare-dyndns.service/timer` | systemd units (15-min DynDNS updates) |
| `install-cloudflare.sh` | One-time install of the timer |
| `www/` | Static site served at the root domain |

## Monitoring

```bash
systemctl list-timers cloudflare-dyndns.timer
journalctl -u cloudflare-dyndns.service -f
tail -f /var/log/cloudflare-dyndns.log
tail -f /var/log/nginx/madtec.org.access.log
```
