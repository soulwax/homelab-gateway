#!/usr/bin/env bash
set -euo pipefail

CF_API="https://api.cloudflare.com/client/v4"
CACHE_FILE="/var/cache/cloudflare-dyndns/last_ips"
LOG_FILE="/var/log/cloudflare-dyndns.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }

load_config() {
    local script_dir env_file legacy_file
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    env_file="${script_dir}/.env"
    legacy_file="${script_dir}/cloudflare-dyndns.conf"

    if [[ -f "$env_file" ]]; then
        # shellcheck source=/dev/null
        source "$env_file"
    elif [[ -f "$legacy_file" ]]; then
        # shellcheck source=/dev/null
        source "$legacy_file"
        : "${CF_ZONE_ID:=${ZONE_ID:-}}"
    else
        echo "Config not found. Expected ${env_file} or ${legacy_file}" >&2
        exit 1
    fi

    : "${CF_TOKEN:?CF_TOKEN is required}"
    : "${CF_ZONE_ID:?CF_ZONE_ID is required}"
    : "${DOMAIN:?DOMAIN is required}"
    : "${IFACE:?IFACE is required}"
    ZONE_ID="$CF_ZONE_ID"
}

detect_ipv6() {
    ip -6 -o addr show dev "$IFACE" scope global 2>/dev/null \
        | awk '
            $0 !~ / temporary / &&
            $0 !~ / deprecated / &&
            $0 !~ / tentative / &&
            $0 !~ / dadfailed / {
                split($4, cidr, "/")
                if (cidr[1] !~ /^(fd|fc)/) {
                    print cidr[1]
                    exit
                }
            }
        '
}

load_config

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

# Stable public IPv6 (non-temporary, non-deprecated, non-ULA)
IPV6=$(detect_ipv6 || true)

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
