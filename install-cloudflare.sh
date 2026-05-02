#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ "$EUID" -eq 0 ]] || { echo "Run as root: sudo bash $0" >&2; exit 1; }

# jq is required
command -v jq &>/dev/null || apt-get install -y jq

install -m 700 "$SCRIPT_DIR/update-cloudflare-dyndns.sh" /usr/local/bin/update-cloudflare-dyndns.sh
install -m 600 "$SCRIPT_DIR/cloudflare-dyndns.conf"      /usr/local/bin/cloudflare-dyndns.conf

sed -i 's|CONF_FILE="$(dirname "$0")/cloudflare-dyndns.conf"|CONF_FILE="/usr/local/bin/cloudflare-dyndns.conf"|' \
    /usr/local/bin/update-cloudflare-dyndns.sh

mkdir -p /var/cache/cloudflare-dyndns
touch /var/log/cloudflare-dyndns.log

install -m 644 "$SCRIPT_DIR/cloudflare-dyndns.service" /etc/systemd/system/cloudflare-dyndns.service
install -m 644 "$SCRIPT_DIR/cloudflare-dyndns.timer"   /etc/systemd/system/cloudflare-dyndns.timer

systemctl daemon-reload
systemctl enable --now cloudflare-dyndns.timer

echo "Installed. Running first update now..."
systemctl start cloudflare-dyndns.service
echo ""
echo "Logs: journalctl -u cloudflare-dyndns.service -f"
echo "      tail -f /var/log/cloudflare-dyndns.log"
