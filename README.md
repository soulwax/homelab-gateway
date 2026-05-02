# your-domain\.com — DynDNS + Subdomain Manager

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
DOMAIN="your-domain\.com"
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
  -d your-domain\.com -d '*.your-domain\.com'
```

---

## Router configuration

This setup relies on IPv6 since residential IPv4 is typically behind CG-NAT. Your router must expose the server's IPv6 address to the internet.

### IPv6 host exposure

Find the setting in your router under **Firewall → IPv6 → Host Exposure** (name varies by vendor) and expose **all TCP+UDP ports** to your server's IPv6 address:

```
Address:  2a00:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx   ← your server's stable IPv6
Subnet:   /64
Protocol: TCP + UDP
Ports:    ALL  (or at minimum 80, 443, and any TCP ports you proxy)
```

To find your server's stable IPv6:

```bash
ip -6 addr show scope global | grep -v temporary | grep -oP 'inet6 \K[0-9a-f:]+(?=/)'
```

> **Note:** The `2a00:…` prefix is assigned by your ISP and can change when your router reboots or renews its prefix delegation. The DynDNS timer handles updating DNS automatically, but you will need to update the router's host exposure entry with the new address if the prefix changes.

### Common router UIs

| Router | Path |
|---|---|
| Fritz!Box | Internet → Freigaben → IPv6-Freigaben |
| Vodafone EasyBox | Firewall → IPv6 → Host-Freigabe |
| Generic | Firewall → IPv6 Firewall → Inbound rules |

### IPv4

IPv4 inbound will only work if your ISP gives you a dedicated public IPv4 (not CG-NAT). If `curl -4 https://api.ipify.org` returns the same IP as your router's WAN address and you can set up port forwarding, add rules for ports 80 and 443. Otherwise, IPv6 is the only inbound path.

---

## Add a subdomain

```bash
# HTTP reverse proxy  →  https://app.your-domain\.com  proxies to localhost:3000
bash add-subdomain.sh app 3000

# TCP passthrough  →  db.your-domain\.com:5432  routes to localhost:5432
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
tail -f /var/log/nginx/your-domain\.com.access.log
```
