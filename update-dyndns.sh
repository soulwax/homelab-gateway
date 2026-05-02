#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="$(dirname "$0")/strato-dyndns.conf"
STRATO_URL="https://dyndns.strato.com/nic/update"
CACHE_FILE="/var/cache/strato-dyndns/last_ips"
LOG_FILE="/var/log/strato-dyndns.log"

if [[ ! -f "$CONF_FILE" ]]; then
    echo "Config file not found: $CONF_FILE" >&2
    exit 1
fi
# shellcheck source=strato-dyndns.conf
source "$CONF_FILE"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }

# Public IPv4 via external lookup (server is behind NAT)
IPV4=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || true)

# Stable public IPv6: global, non-temporary, non-ULA (not fd.../fc...)
IPV6=$(ip -6 addr show dev "$IFACE" scope global 2>/dev/null \
    | grep -v "temporary" \
    | grep -oP 'inet6 \K[0-9a-f:]+(?=/)' \
    | grep -vE '^(fd|fc)' \
    | head -1 || true)

if [[ -z "$IPV4" && -z "$IPV6" ]]; then
    log "ERROR: Could not determine any IP address"
    exit 1
fi

if [[ -n "$IPV4" && -n "$IPV6" ]]; then
    MYIP="$IPV4,$IPV6"
elif [[ -n "$IPV4" ]]; then
    MYIP="$IPV4"
else
    MYIP="$IPV6"
fi

mkdir -p "$(dirname "$CACHE_FILE")"
LAST_IPS=$(cat "$CACHE_FILE" 2>/dev/null || true)

if [[ "$LAST_IPS" == "$MYIP" ]]; then
    log "IPs unchanged ($MYIP), skipping update"
    exit 0
fi

RESPONSE=$(curl -s --max-time 15 \
    --user "$DOMAIN:$PASSWORD" \
    "$STRATO_URL?hostname=$HOSTNAME&myip=$MYIP" 2>/dev/null)

log "Update sent (myip=$MYIP): response=$RESPONSE"

if echo "$RESPONSE" | grep -qE "^(good|nochg)"; then
    echo "$MYIP" > "$CACHE_FILE"
    log "Update successful"
else
    log "ERROR: Unexpected response: $RESPONSE"
    exit 1
fi
