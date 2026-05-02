#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$(dirname "$0")/.env"
CF_API="https://api.cloudflare.com/client/v4"
CACHE_FILE="/var/cache/cloudflare-dyndns/last_ips"
LOG_FILE="/var/log/cloudflare-dyndns.log"

[[ -f "$ENV_FILE" ]] || { echo ".env not found: $ENV_FILE" >&2; exit 1; }
source "$ENV_FILE"
ZONE_ID="$CF_ZONE_ID"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }

cf_api() {
    local method=$1 path=$2 data=${3:-}
    local args=(-s --max-time 15 -X "$method"
        -H "Authorization: Bearer $CF_TOKEN"
        -H "Content-Type: application/json"
        "${CF_API}${path}")
    [[ -n "$data" ]] && args+=(-d "$data")
    curl "${args[@]}"
}

upsert_record() {
    local type=$1 ip=$2
    local existing
    existing=$(cf_api GET "/zones/${ZONE_ID}/dns_records?type=${type}&name=${DOMAIN}")

    local record_id count
    record_id=$(echo "$existing" | jq -r '.result[0].id // empty')
    count=$(echo "$existing"    | jq -r '.result | length')

    local payload
    payload=$(jq -nc --arg t "$type" --arg n "$DOMAIN" --arg c "$ip" \
        '{type:$t, name:$n, content:$c, ttl:60, proxied:false}')

    if [[ -z "$record_id" || "$count" -eq 0 ]]; then
        local resp
        resp=$(cf_api POST "/zones/${ZONE_ID}/dns_records" "$payload")
        if echo "$resp" | jq -e '.success' > /dev/null; then
            log "Created $type $ip"
        else
            log "ERROR creating $type: $(echo "$resp" | jq -r '.errors')"
            return 1
        fi
    else
        local resp
        resp=$(cf_api PUT "/zones/${ZONE_ID}/dns_records/${record_id}" "$payload")
        if echo "$resp" | jq -e '.success' > /dev/null; then
            log "Updated $type $ip"
        else
            log "ERROR updating $type: $(echo "$resp" | jq -r '.errors')"
            return 1
        fi
    fi
}

# Public IPv4 (behind NAT, must use external lookup)
IPV4=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || true)

# Stable public IPv6 (non-temporary, non-ULA)
IPV6=$(ip -6 addr show dev "$IFACE" scope global 2>/dev/null \
    | grep -v "temporary" \
    | grep -oP 'inet6 \K[0-9a-f:]+(?=/)' \
    | grep -vE '^(fd|fc)' \
    | head -1 || true)

[[ -z "$IPV4" && -z "$IPV6" ]] && { log "ERROR: no IP detected"; exit 1; }

MYIP="${IPV4}${IPV4:+,}${IPV6}"   # "v4,v6" or whichever exist

mkdir -p "$(dirname "$CACHE_FILE")"
LAST=$(cat "$CACHE_FILE" 2>/dev/null || true)

if [[ "$LAST" == "$MYIP" ]]; then
    log "IPs unchanged ($MYIP), skipping"
    exit 0
fi

log "IP change detected: $LAST -> $MYIP"

[[ -n "$IPV4" ]] && upsert_record A    "$IPV4"
[[ -n "$IPV6" ]] && upsert_record AAAA "$IPV6"

echo "$MYIP" > "$CACHE_FILE"
log "Done"
