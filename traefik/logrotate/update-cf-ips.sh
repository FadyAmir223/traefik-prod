#!/bin/sh

echo "[$(date)] Checking Cloudflare IPs and Template changes..."

TMP_RAW="/logs/cf_raw.json"
TMP_CONTENT="/logs/cf_ips.tmp"
TMP_NEW="/logs/traefik_new.tmp"
TEMPLATE_FILE="/traefik.template.yml"
ACTUAL_FILE="/traefik.yml"

# Fetch IPs from Cloudflare API
curl -s -o "$TMP_RAW" https://api.cloudflare.com/client/v4/ips

SUCCESS=$(jq -r '.success' "$TMP_RAW")
if [ "$SUCCESS" != "true" ]; then
  echo "[$(date)] Error: Failed to fetch valid IPs."
  rm -f "$TMP_RAW"
  exit 1
fi

jq -r '(.result.ipv4_cidrs[], .result.ipv6_cidrs[]) | "        - \(. )"' "$TMP_RAW" >"$TMP_CONTENT"

# TODO: delete me
if ! grep -q "173.245.48.0" "$TMP_CONTENT"; then
  echo "[$(date)] Error: Missing expected core IP ranges."
  rm -f "$TMP_RAW" "$TMP_CONTENT"
  exit 1
fi

# Generate the new config strictly from the tracked template
awk -v f="$TMP_CONTENT" '
/# cloudflareIPs/ {
    print
    system("cat " f)
    skip = 1
    next
}
/# CF-END/ { skip = 0 }
!skip { print }
' "$TEMPLATE_FILE" >"$TMP_NEW"

# Compare the newly generated file with the active running configuration
if [ -f "$ACTUAL_FILE" ] && cmp -s "$TMP_NEW" "$ACTUAL_FILE"; then
  echo "[$(date)] Configuration is up to date. No action needed."
else
  echo "[$(date)] Changes detected (either IPs updated or Template changed). Updating..."
  cat "$TMP_NEW" >"$ACTUAL_FILE"

  echo "[$(date)] Sending TERM to Traefik (PID 1) to trigger restart..."
  kill -TERM 1
fi

rm -f "$TMP_RAW" "$TMP_CONTENT" "$TMP_NEW"
