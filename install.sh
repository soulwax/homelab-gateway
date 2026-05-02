#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$EUID" -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

install -m 700 "$SCRIPT_DIR/update-dyndns.sh" /usr/local/bin/update-dyndns.sh
install -m 600 "$SCRIPT_DIR/strato-dyndns.conf" /usr/local/bin/strato-dyndns.conf

# Point the installed script at its config in the new location
sed -i 's|CONF_FILE="$(dirname "$0")/strato-dyndns.conf"|CONF_FILE="/usr/local/bin/strato-dyndns.conf"|' \
    /usr/local/bin/update-dyndns.sh

mkdir -p /var/cache/strato-dyndns
touch /var/log/strato-dyndns.log

install -m 644 "$SCRIPT_DIR/strato-dyndns.service" /etc/systemd/system/strato-dyndns.service
install -m 644 "$SCRIPT_DIR/strato-dyndns.timer"   /etc/systemd/system/strato-dyndns.timer

systemctl daemon-reload
systemctl enable --now strato-dyndns.timer

echo "Installed. Running first update now..."
systemctl start strato-dyndns.service
echo "Done. Check logs with: journalctl -u strato-dyndns.service -f"
echo "         or:           tail -f /var/log/strato-dyndns.log"
