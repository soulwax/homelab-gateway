#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$(dirname "$0")/.env"
CF_API="https://api.cloudflare.com/client/v4"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
NGINX_STREAM="/etc/nginx/stream.conf.d"
CERT="/etc/letsencrypt/live/madtec.org/fullchain.pem"
KEY="/etc/letsencrypt/live/madtec.org/privkey.pem"

usage() {
    echo "Usage: $0 <subdomain> <port|tcp:port> [--remove]"
    echo "  HTTP:  $0 app 3000"
    echo "  TCP:   $0 db  tcp:5432"
    exit 1
}

[[ $# -lt 2 ]] && usage
SUB="$1"
ARG="$2"
REMOVE="${3:-}"
FQDN="${SUB}.madtec.org"

# Parse tcp:PORT vs plain PORT
if [[ "$ARG" == tcp:* ]]; then
    MODE="tcp"
    PORT="${ARG#tcp:}"
else
    MODE="http"
    PORT="$ARG"
fi

source "$ENV_FILE"
ZONE_ID="$CF_ZONE_ID"

cf_api() {
    local method=$1 path=$2 data=${3:-}
    local args=(-s --max-time 15 -X "$method"
        -H "Authorization: Bearer $CF_TOKEN"
        -H "Content-Type: application/json"
        "${CF_API}${path}")
    [[ -n "$data" ]] && args+=(-d "$data")
    curl "${args[@]}"
}

# ── Remove mode ───────────────────────────────────────────────────────────────
if [[ "$REMOVE" == "--remove" ]]; then
    echo "Removing $FQDN..."

    RECORD_ID=$(cf_api GET "/zones/${ZONE_ID}/dns_records?type=CNAME&name=${FQDN}" \
        | jq -r '.result[0].id // empty')
    if [[ -n "$RECORD_ID" ]]; then
        cf_api DELETE "/zones/${ZONE_ID}/dns_records/${RECORD_ID}" | jq -r '.success'
        echo "DNS CNAME deleted"
    fi

    sudo rm -f "${NGINX_ENABLED}/${FQDN}" "${NGINX_AVAILABLE}/${FQDN}" \
               "${NGINX_STREAM}/${FQDN}.conf"
    sudo nginx -t && sudo systemctl reload nginx
    echo "Done — $FQDN removed"
    exit 0
fi

# ── DNS CNAME (same for both modes) ──────────────────────────────────────────
echo "Adding $FQDN → localhost:$PORT ($MODE)"

EXISTING=$(cf_api GET "/zones/${ZONE_ID}/dns_records?type=CNAME&name=${FQDN}" \
    | jq -r '.result | length')

if [[ "$EXISTING" -eq 0 ]]; then
    RESP=$(cf_api POST "/zones/${ZONE_ID}/dns_records" \
        "$(jq -nc --arg n "$FQDN" '{"type":"CNAME","name":$n,"content":"madtec.org","ttl":60,"proxied":false}')")
    echo "$RESP" | jq -e '.success' > /dev/null
    echo "DNS CNAME created: $FQDN → madtec.org"
else
    echo "DNS CNAME already exists, skipping"
fi

# ── HTTP mode ─────────────────────────────────────────────────────────────────
if [[ "$MODE" == "http" ]]; then
    sudo tee "${NGINX_AVAILABLE}/${FQDN}" > /dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${FQDN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${FQDN};

    ssl_certificate     ${CERT};
    ssl_certificate_key ${KEY};
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass         http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
    }

    access_log /var/log/nginx/${FQDN}.access.log;
    error_log  /var/log/nginx/${FQDN}.error.log;
}
EOF
    sudo ln -sf "${NGINX_AVAILABLE}/${FQDN}" "${NGINX_ENABLED}/${FQDN}"
    sudo nginx -t && sudo systemctl reload nginx
    echo "Done — https://${FQDN} → localhost:${PORT}"
fi

# ── TCP mode ──────────────────────────────────────────────────────────────────
if [[ "$MODE" == "tcp" ]]; then
    sudo tee "${NGINX_STREAM}/${FQDN}.conf" > /dev/null <<EOF
# ${FQDN} — TCP proxy on port ${PORT}
server {
    listen     ${PORT};
    listen     [::]:${PORT};
    proxy_pass 127.0.0.1:${PORT};
}
EOF
    sudo nginx -t && sudo systemctl reload nginx
    echo "Done — ${FQDN}:${PORT} → localhost:${PORT} (TCP)"
    echo "Note: connect with  psql -h ${FQDN} -p ${PORT} ..."
fi
