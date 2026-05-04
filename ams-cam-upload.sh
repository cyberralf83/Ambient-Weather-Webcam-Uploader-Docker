#!/bin/sh
set -e

# Configuration
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-5}
IMAGE_PATH="/home/root/image.jpg"
MIN_IMAGE_SIZE=${MIN_IMAGE_SIZE:-1024}  # Minimum valid image size in bytes
TIMEOUT=${TIMEOUT:-30}
KEEP_IMAGES=${KEEP_IMAGES:-5}  # Number of images to keep for history
IMAGE_RESIZE=${IMAGE_RESIZE:-}    # Optional: max dimensions (e.g., 1920x1080)
IMAGE_QUALITY=${IMAGE_QUALITY:-}  # Optional: JPEG quality 1-100
STATS_FILE="/home/root/stats"
STATUS_HTML="/var/www/index.html"

# Track temp files for cleanup on unexpected exit
NETRC_FILE=""
PROCESS_TEMP_FILE=""
DOWNLOAD_TEMP_FILE=""
STATUS_TMP_FILE=""
cleanup() {
    [ -n "$NETRC_FILE" ] && rm -f "$NETRC_FILE" || true
    [ -n "$PROCESS_TEMP_FILE" ] && rm -f "$PROCESS_TEMP_FILE" || true
    [ -n "$DOWNLOAD_TEMP_FILE" ] && rm -f "$DOWNLOAD_TEMP_FILE" || true
    [ -n "$STATUS_TMP_FILE" ] && rm -f "$STATUS_TMP_FILE" || true
}
trap cleanup EXIT INT TERM

# Single-instance lock — exit silently if another tick is still running.
# flock holds the lock for the script's lifetime via fd 9.
LOCK_FILE="/tmp/ams-cam-upload.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another upload run is in progress, skipping this tick"
    exit 0
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error logging function
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Cleanup old images
cleanup_old_images() {
    if [ -d "/home/root/archive" ]; then
        log "Cleaning up old images, keeping last $KEEP_IMAGES"
        ls -t /home/root/archive/image_*.jpg 2>/dev/null | tail -n +$((KEEP_IMAGES + 1)) | xargs -r rm -f
    fi
}

# Download image with retry logic.
# Writes to $IMAGE_PATH atomically via a sibling temp file so concurrent readers
# (the status page's <img>) never see a half-written JPEG.
download_image() {
    local attempt=1
    DOWNLOAD_TEMP_FILE="${IMAGE_PATH}.downloading"

    while [ $attempt -le $MAX_RETRIES ]; do
        log "Downloading image from $INPUT_IP_ADDRESS (attempt $attempt/$MAX_RETRIES)"

        if wget "$INPUT_IP_ADDRESS" \
            --header 'Cookie: allow-download=1' \
            --timeout=$TIMEOUT \
            --tries=1 \
            -O "$DOWNLOAD_TEMP_FILE" \
            -q 2>/dev/null; then

            # Validate downloaded file
            if [ -f "$DOWNLOAD_TEMP_FILE" ]; then
                FILE_SIZE=$(stat -c%s "$DOWNLOAD_TEMP_FILE" 2>/dev/null || echo 0)

                if [ "$FILE_SIZE" -ge "$MIN_IMAGE_SIZE" ]; then
                    # Verify it's actually an image file
                    FILE_TYPE=$(file -b --mime-type "$DOWNLOAD_TEMP_FILE" 2>/dev/null || echo "unknown")

                    if echo "$FILE_TYPE" | grep -q "image/"; then
                        mv "$DOWNLOAD_TEMP_FILE" "$IMAGE_PATH"
                        DOWNLOAD_TEMP_FILE=""
                        log "Successfully downloaded image ($FILE_SIZE bytes)"
                        return 0
                    else
                        log_error "Downloaded file is not a valid image (type: $FILE_TYPE)"
                    fi
                else
                    log_error "Downloaded file is too small ($FILE_SIZE bytes, minimum: $MIN_IMAGE_SIZE bytes)"
                fi
            else
                log_error "Downloaded file not found"
            fi
        else
            log_error "wget command failed"
        fi

        rm -f "$DOWNLOAD_TEMP_FILE"

        if [ $attempt -lt $MAX_RETRIES ]; then
            log "Waiting $RETRY_DELAY seconds before retry..."
            sleep $RETRY_DELAY
        fi

        attempt=$((attempt + 1))
    done

    DOWNLOAD_TEMP_FILE=""
    log_error "Failed to download image after $MAX_RETRIES attempts"
    return 1
}

# Process image (resize and/or quality adjustment)
# Non-fatal: uploads original if processing fails
process_image() {
    # Skip if neither option is set
    [ -z "$IMAGE_RESIZE" ] && [ -z "$IMAGE_QUALITY" ] && return 0

    # Detect ImageMagick binary (IM7 uses magick, IM6 uses convert)
    local magick_bin=""
    if command -v magick > /dev/null 2>&1; then
        magick_bin="magick"
    elif command -v convert > /dev/null 2>&1; then
        magick_bin="convert"
    else
        log_error "ImageMagick not found, skipping image processing"
        return 0
    fi

    local original_size
    original_size=$(stat -c%s "$IMAGE_PATH" 2>/dev/null || echo "unknown")

    log "Processing image: resize=${IMAGE_RESIZE:-unchanged} quality=${IMAGE_QUALITY:-unchanged}"

    # Write to temp file then atomic mv (never process in-place)
    PROCESS_TEMP_FILE="${IMAGE_PATH}.processing"

    # Run ImageMagick — `if !` form so a crash is caught and logged rather than
    # silently bubbling up and being swallowed by the caller's `|| true`.
    local magick_failed=0
    if [ -n "$IMAGE_RESIZE" ] && [ -n "$IMAGE_QUALITY" ]; then
        "$magick_bin" "$IMAGE_PATH" -resize "${IMAGE_RESIZE}>" -quality "$IMAGE_QUALITY" "$PROCESS_TEMP_FILE" || magick_failed=1
    elif [ -n "$IMAGE_RESIZE" ]; then
        "$magick_bin" "$IMAGE_PATH" -resize "${IMAGE_RESIZE}>" "$PROCESS_TEMP_FILE" || magick_failed=1
    else
        "$magick_bin" "$IMAGE_PATH" -quality "$IMAGE_QUALITY" "$PROCESS_TEMP_FILE" || magick_failed=1
    fi

    if [ "$magick_failed" -ne 0 ]; then
        rm -f "$PROCESS_TEMP_FILE"
        PROCESS_TEMP_FILE=""
        log_error "ImageMagick processing failed, uploading original"
        return 0
    fi

    # Validate processed output before replacing original
    local new_size
    new_size=$(stat -c%s "$PROCESS_TEMP_FILE" 2>/dev/null || echo 0)
    if [ "$new_size" -lt "$MIN_IMAGE_SIZE" ]; then
        rm -f "$PROCESS_TEMP_FILE"
        PROCESS_TEMP_FILE=""
        log_error "Processed image too small (${new_size} bytes), uploading original"
        return 0
    fi

    mv "$PROCESS_TEMP_FILE" "$IMAGE_PATH"
    PROCESS_TEMP_FILE=""
    log "Image processed: ${original_size} -> ${new_size} bytes"
}

# Upload image with retry logic
upload_image() {
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        log "Uploading image to $SERVER:$PORT (attempt $attempt/$MAX_RETRIES)"

        # Use .netrc to avoid exposing credentials in process list
        NETRC_FILE=$(mktemp) || {
            log_error "Failed to create temporary .netrc file"
            return 1
        }
        printf "machine %s login %s password %s\n" "$SERVER" "$USERNAME" "$PASSWORD" > "$NETRC_FILE"
        chmod 600 "$NETRC_FILE"

        if curl -T "$IMAGE_PATH" \
            --netrc-file "$NETRC_FILE" \
            "ftp://$SERVER:$PORT/" \
            --connect-timeout $TIMEOUT \
            --max-time $((TIMEOUT * 2)) \
            --silent \
            --show-error \
            --ftp-create-dirs; then
            rm -f "$NETRC_FILE"
            NETRC_FILE=""

            log "Successfully uploaded image to Ambient Weather"

            # Archive the uploaded image
            mkdir -p /home/root/archive
            TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
            cp "$IMAGE_PATH" "/home/root/archive/image_${TIMESTAMP}.jpg"

            return 0
        else
            rm -f "$NETRC_FILE"
            NETRC_FILE=""
            log_error "Upload failed"
        fi

        if [ $attempt -lt $MAX_RETRIES ]; then
            log "Waiting $RETRY_DELAY seconds before retry..."
            sleep $RETRY_DELAY
        fi

        attempt=$((attempt + 1))
    done

    log_error "Failed to upload image after $MAX_RETRIES attempts"
    return 1
}

# POSIX-safe single-quote escape for embedding a value inside '...'.
# Example: foo'bar -> foo'\''bar  (closes the quote, emits literal ', reopens).
sq_escape() {
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

# Update persistent counters file with the result of this run.
# All string values are written single-quoted so a `.` source treats them
# literally — no expansion, no command substitution, no injection vector.
update_stats() {
    [ "${STATUS_ENABLED:-true}" = "true" ] || return 0

    local status="$1" duration="$2" error="$3"

    if [ ! -f "$STATS_FILE" ]; then
        printf "STAT_TOTAL=0\nSTAT_SUCCESS=0\nSTAT_DOWNLOAD_FAILED=0\nSTAT_UPLOAD_FAILED=0\nSTAT_FIRST_RUN='%s'\n" \
            "$(sq_escape "$(date '+%Y-%m-%d %H:%M:%S')")" \
            > "$STATS_FILE"
    fi

    # shellcheck disable=SC1090
    . "$STATS_FILE"

    STAT_TOTAL=$(( ${STAT_TOTAL:-0} + 1 ))
    case "$status" in
        success)         STAT_SUCCESS=$(( ${STAT_SUCCESS:-0} + 1 )) ;;
        download_failed) STAT_DOWNLOAD_FAILED=$(( ${STAT_DOWNLOAD_FAILED:-0} + 1 )) ;;
        upload_failed)   STAT_UPLOAD_FAILED=$(( ${STAT_UPLOAD_FAILED:-0} + 1 )) ;;
    esac

    {
        printf "STAT_TOTAL=%s\n"            "$STAT_TOTAL"
        printf "STAT_SUCCESS=%s\n"          "$STAT_SUCCESS"
        printf "STAT_DOWNLOAD_FAILED=%s\n"  "$STAT_DOWNLOAD_FAILED"
        printf "STAT_UPLOAD_FAILED=%s\n"    "$STAT_UPLOAD_FAILED"
        printf "STAT_FIRST_RUN='%s'\n"      "$(sq_escape "${STAT_FIRST_RUN:-}")"
        printf "STAT_LAST_STATUS='%s'\n"    "$(sq_escape "$status")"
        printf "STAT_LAST_TIMESTAMP='%s'\n" "$(sq_escape "$(date '+%Y-%m-%d %H:%M:%S')")"
        printf "STAT_LAST_DURATION=%s\n"    "$duration"
        printf "STAT_LAST_ERROR='%s'\n"     "$(sq_escape "$error")"
    } > "$STATS_FILE"
}

# HTML-escape stdin (& < >). Used for any field that could contain log content.
html_escape() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# Render the static status page atomically, branded per BRAND.md.
render_status_page() {
    [ "${STATUS_ENABLED:-true}" = "true" ] || return 0
    [ -d /var/www ] || return 0

    # shellcheck disable=SC1090
    [ -f "$STATS_FILE" ] && . "$STATS_FILE"

    local image_age="&mdash;" image_size="&mdash;"
    if [ -f "$IMAGE_PATH" ]; then
        image_age="$(( $(date +%s) - $(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo 0) ))s"
        image_size="$(stat -c%s "$IMAGE_PATH" 2>/dev/null || echo 0) B"
    fi

    local log_tail=""
    if [ -f /var/log/ams-cam-upload.log ]; then
        log_tail=$(tail -n 20 /var/log/ams-cam-upload.log 2>/dev/null | html_escape)
    fi

    # Status pill: pine on success, ember on any failure, ash before first run
    local pill_class="ash"
    case "${STAT_LAST_STATUS:-}" in
        success)         pill_class="pine" ;;
        download_failed|upload_failed) pill_class="ember" ;;
    esac
    local pill_text="${STAT_LAST_STATUS:-no runs yet}"

    local success_rate="&mdash;"
    if [ "${STAT_TOTAL:-0}" -gt 0 ]; then
        success_rate="$(( ${STAT_SUCCESS:-0} * 100 / STAT_TOTAL ))%"
    fi

    local error_banner=""
    if [ -n "${STAT_LAST_ERROR:-}" ]; then
        local err_html
        err_html=$(printf '%s' "$STAT_LAST_ERROR" | html_escape)
        error_banner="<div class=\"error-banner\"><div class=\"eyebrow\">Last error</div><div class=\"msg\">${err_html}</div></div>"
    fi

    # Cache key is the image's mtime — the URL only changes when the image
    # actually changes, so a failed download doesn't re-fetch the stale file.
    local cache_key="0"
    local snapshot_block
    if [ -f "$IMAGE_PATH" ]; then
        cache_key=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo 0)
        snapshot_block="<div class=\"snapshot\"><img src=\"image.jpg?t=${cache_key}\" alt=\"Latest webcam snapshot\" onerror=\"this.style.display='none'\"></div>"
    else
        snapshot_block="<div class=\"snapshot\"><div class=\"empty\">no snapshot captured yet</div></div>"
    fi

    STATUS_TMP_FILE="${STATUS_HTML}.tmp"
    cat > "$STATUS_TMP_FILE" <<HTML
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="30">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>mj/cam &middot; webcam uploader</title>
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="status.css">
</head>
<body>
<header class="hero">
  <div class="hero-inner">
    <div class="mark-row">
      <div class="mark-lockup">mj<span class="slash">/</span><span class="name">cam</span></div>
      <span class="live-dot">live</span>
    </div>
    <div class="eyebrow">status</div>
    <h1>Snapshots, on schedule.</h1>
    <p class="tagline">Webcam to Ambient Weather, every <code>${INTERVAL_MINUTES:+${INTERVAL_MINUTES} min}${INTERVAL_MINUTES:-${CRON_SCHEDULE:-cron}}</code>.</p>
  </div>
</header>

<main class="shell">
  <p class="meta-line">Auto-refreshes every 30 seconds &middot; rendered $(date '+%Y-%m-%d %H:%M:%S %Z')</p>

  ${error_banner}

  <h2>Last run</h2>
  <div class="grid">
    <div class="card"><div class="label">Status</div><div class="value"><span class="pill ${pill_class}">${pill_text}</span></div></div>
    <div class="card"><div class="label">Timestamp</div><div class="value-sm">${STAT_LAST_TIMESTAMP:-&mdash;}</div></div>
    <div class="card"><div class="label">Duration</div><div class="value">${STAT_LAST_DURATION:-&mdash;}s</div></div>
    <div class="card"><div class="label">Image age</div><div class="value">${image_age}</div></div>
    <div class="card"><div class="label">Image size</div><div class="value">${image_size}</div></div>
  </div>

  <h2>Since container start</h2>
  <div class="grid">
    <div class="card signal"><div class="label">Total runs</div><div class="value">${STAT_TOTAL:-0}</div></div>
    <div class="card pine"><div class="label">Successes</div><div class="value">${STAT_SUCCESS:-0}</div></div>
    <div class="card ember"><div class="label">Download fails</div><div class="value">${STAT_DOWNLOAD_FAILED:-0}</div></div>
    <div class="card ember"><div class="label">Upload fails</div><div class="value">${STAT_UPLOAD_FAILED:-0}</div></div>
    <div class="card"><div class="label">Success rate</div><div class="value">${success_rate}</div></div>
  </div>

  <h2>Latest snapshot</h2>
  ${snapshot_block}

  <h2>Recent log</h2>
  <pre class="log">${log_tail}</pre>

  <footer class="footer">
    <span class="mark">mj</span>
    <span class="sep">&middot;</span>
    <span>schedule <code>${CRON_SCHEDULE:-&mdash;}</code></span>
    <span class="sep">&middot;</span>
    <span>server <code>${SERVER}:${PORT}</code></span>
    <span class="sep">&middot;</span>
    <span>first run ${STAT_FIRST_RUN:-&mdash;}</span>
  </footer>
</main>
</body>
</html>
HTML

    mv "$STATUS_TMP_FILE" "$STATUS_HTML"
    STATUS_TMP_FILE=""
}

# Main execution
RUN_START=$(date +%s)
log "=== Starting Ambient Weather Webcam Upload ==="
log "Server: $SERVER:$PORT"
log "Webcam: $INPUT_IP_ADDRESS"

# Cleanup old archived images
cleanup_old_images

RUN_STATUS="success"
RUN_ERROR=""

if ! download_image; then
    RUN_STATUS="download_failed"
    RUN_ERROR="Could not download image"
else
    # Process image (resize/quality) if configured — non-fatal
    process_image || true

    if ! upload_image; then
        RUN_STATUS="upload_failed"
        RUN_ERROR="Could not upload image"
    fi
fi

RUN_DURATION=$(( $(date +%s) - RUN_START ))

# Status reporting must never break the upload pipeline
update_stats "$RUN_STATUS" "$RUN_DURATION" "$RUN_ERROR" || true
render_status_page || true

if [ "$RUN_STATUS" != "success" ]; then
    log_error "Script failed: $RUN_ERROR"
    exit 1
fi

log "=== Upload completed successfully ==="
exit 0
