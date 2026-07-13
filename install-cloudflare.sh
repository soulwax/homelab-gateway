#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ "$EUID" -eq 0 ]] || { echo "Run as root: sudo bash $0" >&2; exit 1; }

# jq is required
command -v jq &>/dev/null || apt-get install -y jq

install -m 700 "$SCRIPT_DIR/update-cloudflare-dyndns.sh" /usr/local/bin/update-cloudflare-dyndns.sh

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    install -m 600 "$SCRIPT_DIR/.env" /usr/local/bin/.env
elif [[ -f "$SCRIPT_DIR/cloudflare-dyndns.conf" ]]; then
    install -m 600 "$SCRIPT_DIR/cloudflare-dyndns.conf" /usr/local/bin/cloudflare-dyndns.conf
else
    echo "No Cloudflare config found. Create .env or cloudflare-dyndns.conf first." >&2
    exit 1
fi

mkdir -p /var/cache/cloudflare-dyndns
touch /var/log/cloudflare-dyndns.log

install -m 644 "$SCRIPT_DIR/cloudflare-dyndns.service" /etc/systemd/system/cloudflare-dyndns.service
install -m 644 "$SCRIPT_DIR/cloudflare-dyndns.timer"   /etc/systemd/system/cloudflare-dyndns.timer

# NetworkManager dispatcher hook: fire the updater immediately on (re)connect.
# Must be root-owned and 0755 (NM ignores group/world-writable scripts).
if [[ -d /etc/NetworkManager/dispatcher.d ]]; then
    install -m 755 "$SCRIPT_DIR/90-cloudflare-dyndns" /etc/NetworkManager/dispatcher.d/90-cloudflare-dyndns
    echo "Installed NetworkManager dispatcher hook."
else
    echo "NetworkManager dispatcher.d not found; skipping instant-update hook." >&2
fi

systemctl daemon-reload
systemctl enable --now cloudflare-dyndns.timer

echo "Installed. Running first update now..."
systemctl start cloudflare-dyndns.service
echo ""
echo "Logs: journalctl -u cloudflare-dyndns.service -f"
echo "      tail -f /var/log/cloudflare-dyndns.log"
