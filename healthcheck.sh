#!/bin/sh

# Health check script for Docker container
# Returns 0 if healthy, 1 if unhealthy

# Configuration
MAX_AGE=${HEALTHCHECK_MAX_AGE:-300}  # Maximum age of last successful upload in seconds (default: 5 minutes)
IMAGE_PATH="/home/root/image.jpg"
LOG_FILE="/var/log/ams-cam-upload.log"

# Check if cron is running
if ! pgrep crond > /dev/null; then
    echo "UNHEALTHY: crond is not running"
    exit 1
fi

# Check if image file exists
if [ ! -f "$IMAGE_PATH" ]; then
    echo "UNHEALTHY: No image file found at $IMAGE_PATH"
    exit 1
fi

# Check age of image file
IMAGE_AGE=$(( $(date +%s) - $(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo 0) ))

if [ "$IMAGE_AGE" -gt "$MAX_AGE" ]; then
    echo "UNHEALTHY: Image file is too old ($IMAGE_AGE seconds, max: $MAX_AGE)"
    exit 1
fi

# Check for recent errors in log (if log exists)
if [ -f "$LOG_FILE" ]; then
    # Check if there are only errors in the last 10 lines
    RECENT_ERRORS=$(tail -n 10 "$LOG_FILE" 2>/dev/null | grep -c "ERROR:" || echo 0)
    RECENT_SUCCESS=$(tail -n 10 "$LOG_FILE" 2>/dev/null | grep -c "Upload completed successfully" || echo 0)

    if [ "$RECENT_ERRORS" -gt 5 ] && [ "$RECENT_SUCCESS" -eq 0 ]; then
        echo "UNHEALTHY: Multiple recent errors without successful uploads"
        exit 1
    fi
fi

echo "HEALTHY: Container is functioning normally"
exit 0
