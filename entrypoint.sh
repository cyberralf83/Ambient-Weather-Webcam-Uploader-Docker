#!/bin/sh

# Default cron schedule: every 2 minutes
CRON_SCHEDULE=${CRON_SCHEDULE:-"*/2 * * * *"}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Ambient Weather Webcam Uploader"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron schedule: $CRON_SCHEDULE"

# Run the script once immediately
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running initial upload..."
/usr/local/bin/ams-cam-upload.sh || echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initial upload failed, will retry on schedule"

# Create a cron job with configurable schedule
echo "$CRON_SCHEDULE /usr/local/bin/ams-cam-upload.sh >> /var/log/ams-cam-upload.log 2>&1" >> /etc/crontabs/root

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron job configured, starting cron daemon..."

# Run cron in the foreground
crond -f -l 2
