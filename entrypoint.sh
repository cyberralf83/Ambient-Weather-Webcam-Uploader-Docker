#!/bin/sh

# INTERVAL_MINUTES is the simple "upload every N minutes" knob. If set, it
# wins over CRON_SCHEDULE. Valid range: 1-60 (cron's */N syntax only spans
# the minute field). For longer intervals or specific-time schedules, set
# CRON_SCHEDULE directly instead.
if [ -n "$INTERVAL_MINUTES" ]; then
    if ! echo "$INTERVAL_MINUTES" | grep -qE '^[0-9]+$' || \
       [ "$INTERVAL_MINUTES" -lt 1 ] || [ "$INTERVAL_MINUTES" -gt 60 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: INTERVAL_MINUTES must be a number between 1 and 60. Use CRON_SCHEDULE for hour/day/etc. schedules."
        exit 1
    fi
    CRON_SCHEDULE="*/$INTERVAL_MINUTES * * * *"
fi

# Default cron schedule: every 2 minutes
CRON_SCHEDULE=${CRON_SCHEDULE:-"*/2 * * * *"}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Ambient Weather Webcam Uploader"
if [ -n "$INTERVAL_MINUTES" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Upload interval: every $INTERVAL_MINUTES minute(s) (CRON_SCHEDULE=$CRON_SCHEDULE)"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron schedule: $CRON_SCHEDULE"
fi

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

# Validate optional IMAGE_RESIZE format (e.g., 1920x1080)
if [ -n "$IMAGE_RESIZE" ]; then
    if ! echo "$IMAGE_RESIZE" | grep -qE '^[0-9]+x[0-9]+$'; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: IMAGE_RESIZE must be in WIDTHxHEIGHT format (e.g., 1920x1080)"
        exit 1
    fi
fi

# Validate optional IMAGE_QUALITY range (1-100)
if [ -n "$IMAGE_QUALITY" ]; then
    if ! echo "$IMAGE_QUALITY" | grep -qE '^[0-9]+$' || [ "$IMAGE_QUALITY" -lt 1 ] || [ "$IMAGE_QUALITY" -gt 100 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: IMAGE_QUALITY must be a number between 1 and 100"
        exit 1
    fi
fi

# Validate optional STATUS_PORT (1-65535)
if [ -n "$STATUS_PORT" ]; then
    if ! echo "$STATUS_PORT" | grep -qE '^[0-9]+$' || [ "$STATUS_PORT" -lt 1 ] || [ "$STATUS_PORT" -gt 65535 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: STATUS_PORT must be a number between 1 and 65535"
        exit 1
    fi
fi

# Export environment variables so cron jobs can access them
# Quote values to handle passwords/URLs with special characters
ENV_FILE="/etc/environment"
install -m 600 /dev/null "$ENV_FILE"
env | grep -E '^(INPUT_IP_ADDRESS|SERVER|PORT|USERNAME|PASSWORD|MAX_RETRIES|RETRY_DELAY|TIMEOUT|MIN_IMAGE_SIZE|KEEP_IMAGES|HEALTHCHECK_MAX_AGE|TZ|IMAGE_RESIZE|IMAGE_QUALITY|STATUS_ENABLED|STATUS_PORT|INTERVAL_MINUTES|CRON_SCHEDULE)=' | \
  while IFS='=' read -r key value; do
    printf "export %s='%s'\n" "$key" "$(echo "$value" | sed "s/'/'\\\\''/g")"
  done > "$ENV_FILE"

if [ ! -s "$ENV_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: Failed to write environment to $ENV_FILE"
    exit 1
fi

# Start status web server (busybox httpd) — opt out with STATUS_ENABLED=false
if [ "${STATUS_ENABLED:-true}" = "true" ]; then
    mkdir -p /var/www
    # Symlink the working image so httpd serves the latest snapshot
    ln -sf /home/root/image.jpg /var/www/image.jpg
    # Placeholder until first run renders the real page (uses the same brand stylesheet)
    cat > /var/www/index.html <<'PLACEHOLDER'
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="5">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>mj/cam · starting up</title>
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="status.css">
</head>
<body>
<header class="hero">
  <div class="hero-inner">
    <div class="mark-row">
      <div class="mark-lockup">mj<span class="slash">/</span><span class="name">cam</span></div>
      <span class="live-dot">starting</span>
    </div>
    <div class="eyebrow">status &middot; warming up</div>
    <h1>Snapshots, on schedule.</h1>
    <p class="tagline">Waiting for the first upload to complete&hellip;</p>
  </div>
</header>
<main class="shell">
  <p class="meta-line">This page will refresh in a few seconds.</p>
</main>
</body>
</html>
PLACEHOLDER
    STATUS_HTTPD_PORT="${STATUS_PORT:-8080}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting status httpd on port $STATUS_HTTPD_PORT"
    # On Alpine, the httpd applet ships as a separate /usr/sbin/httpd binary
    # in the busybox-extras package — invoking it via `busybox httpd` fails
    # because the main busybox binary doesn't include the applet. Call the
    # standalone binary instead. It daemonizes by default; a non-zero exit
    # means launch itself failed (e.g. port already bound). The upload
    # pipeline still works, so log a warning rather than aborting.
    if ! httpd -p "$STATUS_HTTPD_PORT" -h /var/www; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: status httpd failed to start (port $STATUS_HTTPD_PORT). Status page will be unavailable; uploads continue."
    fi
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
