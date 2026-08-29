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
    : "${ADDITIONAL_DOMAINS:=}"
    ZONE_ID="$CF_ZONE_ID"
}

detect_ipv6() {
    # Prefer the stable managed address (mngtmpaddr) so AAAA does not flap to a
    # short-lived privacy address. Retry a few times after reconnects while DAD
    # may still mark the new address tentative.
    local attempt addr
    for attempt in 1 2 3 4 5; do
        addr=$(ip -6 -o addr show dev "$IFACE" scope global 2>/dev/null \
            | awk '
                $0 ~ / temporary /  { next }
                $0 ~ / deprecated / { next }
                $0 ~ / tentative /  { next }
                $0 ~ / dadfailed /  { next }
                {
                    split($4, cidr, "/")
                    if (cidr[1] ~ /^(fd|fc)/) next
                    if ($0 ~ /mngtmpaddr/) { print cidr[1]; exit }
                    if (fallback == "") fallback = cidr[1]
                }
                END { if (fallback != "") print fallback }')
        [[ -n "$addr" ]] && { printf '%s' "$addr"; return 0; }
        sleep 2
    done
    return 0
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
    local zone_id=$1 domain=$2 type=$3 ip=$4
    local existing record_id count payload resp
    existing=$(cf_api GET "/zones/${zone_id}/dns_records?type=${type}&name=${domain}")
    record_id=$(echo "$existing" | jq -r '.result[0].id // empty')
    count=$(echo "$existing" | jq -r '.result | length')
    payload=$(jq -nc --arg t "$type" --arg n "$domain" --arg c "$ip" \
        '{type:$t, name:$n, content:$c, ttl:60, proxied:false}')

    if [[ -z "$record_id" || "$count" -eq 0 ]]; then
        resp=$(cf_api POST "/zones/${zone_id}/dns_records" "$payload")
        if echo "$resp" | jq -e '.success' > /dev/null; then
            log "Created ${domain} $type $ip"
        else
            log "ERROR creating ${domain} $type: $(echo "$resp" | jq -r '.errors')"
            return 1
        fi
    else
        resp=$(cf_api PUT "/zones/${zone_id}/dns_records/${record_id}" "$payload")
        if echo "$resp" | jq -e '.success' > /dev/null; then
            log "Updated ${domain} $type $ip"
        else
            log "ERROR updating ${domain} $type: $(echo "$resp" | jq -r '.errors')"
            return 1
        fi
    fi
}

managed_domains() {
    printf '%s:%s\n' "$DOMAIN" "$ZONE_ID"

    local entry domain zone_id
    for entry in ${ADDITIONAL_DOMAINS//,/ }; do
        [[ -n "$entry" ]] || continue
        domain="${entry%%:*}"
        zone_id="${entry#*:}"
        if [[ -z "$domain" || -z "$zone_id" || "$domain" == "$zone_id" ]]; then
            log "ERROR invalid ADDITIONAL_DOMAINS entry: $entry"
            return 1
        fi
        printf '%s:%s\n' "$domain" "$zone_id"
    done
}

# Public IPv4 (behind NAT, must use external lookup). Try several providers and
# retry because a single provider can be briefly unreachable after reconnects.
detect_ipv4() {
    local attempt url ip
    for attempt in 1 2 3; do
        for url in https://api.ipify.org https://ipv4.icanhazip.com https://v4.ident.me; do
            ip=$(curl -4 -s --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]')
            [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { printf '%s' "$ip"; return 0; }
        done
        sleep 2
    done
    return 0
}
IPV4=$(detect_ipv4 || true)

# Stable public IPv6 (non-temporary, non-deprecated, non-ULA)
IPV6=$(detect_ipv6 || true)

[[ -z "$IPV4" && -z "$IPV6" ]] && { log "ERROR: no IP detected"; exit 1; }

MYIP="${IPV4}${IPV4:+,}${IPV6}"
TARGETS=$(managed_domains)
CACHE_VALUE="${MYIP}|${TARGETS//$'\n'/,}"

mkdir -p "$(dirname "$CACHE_FILE")"
LAST=$(cat "$CACHE_FILE" 2>/dev/null || true)

if [[ "$LAST" == "$CACHE_VALUE" ]]; then
    log "IPs unchanged ($MYIP), skipping"
    exit 0
fi

log "IP change detected: $LAST -> $MYIP"

while IFS=: read -r domain zone_id; do
    [[ -n "$domain" && -n "$zone_id" ]] || continue
    [[ -n "$IPV4" ]] && upsert_record "$zone_id" "$domain" A "$IPV4"
    [[ -n "$IPV6" ]] && upsert_record "$zone_id" "$domain" AAAA "$IPV6"
done <<< "$TARGETS"

echo "$CACHE_VALUE" > "$CACHE_FILE"
log "Done"
