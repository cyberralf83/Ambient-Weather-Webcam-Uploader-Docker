#!/bin/sh

# Default cron schedule: every 2 minutes
CRON_SCHEDULE=${CRON_SCHEDULE:-"*/2 * * * *"}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Ambient Weather Webcam Uploader"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron schedule: $CRON_SCHEDULE"

# Validate required environment variables
for var in INPUT_IP_ADDRESS SERVER PORT USERNAME PASSWORD; do
    val=$(printenv "$var" || true)
    if [ -z "$val" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: Required environment variable $var is not set"
        exit 1
    fi
done

# Validate CRON_SCHEDULE format to prevent command injection
# Allows standard 5-field cron expressions with optional day/month names (MON, JAN, etc.)
if ! echo "$CRON_SCHEDULE" | grep -qE '^[0-9a-zA-Z*/,-]+ [0-9a-zA-Z*/,-]+ [0-9a-zA-Z*/,-]+ [0-9a-zA-Z*/,-]+ [0-9a-zA-Z*/,-]+$'; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: Invalid CRON_SCHEDULE format: $CRON_SCHEDULE"
    echo "Expected: 5-field cron expression (e.g., '*/2 * * * *' or '0 6 * * MON-FRI')"
    exit 1
fi

# Validate INPUT_IP_ADDRESS is an HTTP(S) URL
case "$INPUT_IP_ADDRESS" in
    http://*|https://*) ;;
    *)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: INPUT_IP_ADDRESS must start with http:// or https://"
        exit 1
        ;;
esac

# Validate PORT is numeric and in valid range
if ! echo "$PORT" | grep -qE '^[0-9]+$' || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: PORT must be a number between 1 and 65535"
    exit 1
fi

# Validate SERVER contains only valid hostname characters
if echo "$SERVER" | grep -qE '[^a-zA-Z0-9._-]'; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: SERVER contains invalid characters"
    exit 1
fi

# Export environment variables so cron jobs can access them
# Quote values to handle passwords/URLs with special characters
ENV_FILE="/etc/environment"
install -m 600 /dev/null "$ENV_FILE"
env | grep -E '^(INPUT_IP_ADDRESS|SERVER|PORT|USERNAME|PASSWORD|MAX_RETRIES|RETRY_DELAY|TIMEOUT|MIN_IMAGE_SIZE|KEEP_IMAGES|HEALTHCHECK_MAX_AGE|TZ)=' | \
  while IFS='=' read -r key value; do
    printf "export %s='%s'\n" "$key" "$(echo "$value" | sed "s/'/'\\\\''/g")"
  done > "$ENV_FILE"

if [ ! -s "$ENV_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: Failed to write environment to $ENV_FILE"
    exit 1
fi

# Run the script once immediately
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running initial upload..."
/usr/local/bin/ams-cam-upload.sh || echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initial upload failed, will retry on schedule"

# Create cron jobs
# Use && so the script won't run if env sourcing fails
echo "$CRON_SCHEDULE . /etc/environment && /usr/local/bin/ams-cam-upload.sh >> /var/log/ams-cam-upload.log 2>&1" > /etc/crontabs/root
# Run logrotate every 6 hours to prevent log file growth
echo "0 */6 * * * /usr/sbin/logrotate /etc/logrotate.d/ams-cam-upload > /dev/null 2>&1" >> /etc/crontabs/root

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron jobs configured, starting cron daemon..."

# Run cron in the foreground
crond -f -l 2
