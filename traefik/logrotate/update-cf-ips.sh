#!/bin/sh

RAW_RESPONSE="/logs/cf_raw.json"
TMP_IPS="/logs/cf_ips.json"
TMP_FILE="/logs/traefik.tmp.yml"
TEMPLATE_FILE="/traefik/traefik.yml"
ACTUAL_FILE="/traefik/traefik.generated.yml"

curl -s -o "$RAW_RESPONSE" https://api.cloudflare.com/client/v4/ips

SUCCESS=$(jq -r '.success' "$RAW_RESPONSE")
if [ "$SUCCESS" != "true" ]; then
  echo "[$(date)] failed to fetch IPs"
  rm -f "$RAW_RESPONSE"
  exit 1
fi

jq -r '(.result.ipv4_cidrs[], .result.ipv6_cidrs[]) | "        - \(. )"' "$RAW_RESPONSE" >"$TMP_IPS"

# generate traefik.generated.yml strictly from the tracked template
awk -v f="$TMP_IPS" '
/# cloudflareIPs-start/ {
    print
    system("cat " f)
    skip = 1
    next
}
/# cloudflareIPs-end/ { skip = 0 }
!skip { print }
' "$TEMPLATE_FILE" >"$TMP_FILE"

# restart traefik if file changed
if [ ! -f "$ACTUAL_FILE" ] || ! cmp -s "$TMP_FILE" "$ACTUAL_FILE"; then
  cat "$TMP_FILE" >"$ACTUAL_FILE"

  # only restart if it was inside traefik-logrotate not init
  if grep -q "traefik" /proc/1/comm 2>/dev/null; then
    echo "[$(date)] restarting traefik"
    kill -TERM 1
  fi
fi

rm -f "$RAW_RESPONSE" "$TMP_IPS" "$TMP_FILE"
