#!/bin/sh
set -e

# Configuration
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-5}
IMAGE_PATH="/home/root/image.jpg"
MIN_IMAGE_SIZE=${MIN_IMAGE_SIZE:-1024}  # Minimum valid image size in bytes
TIMEOUT=${TIMEOUT:-30}
KEEP_IMAGES=${KEEP_IMAGES:-5}  # Number of images to keep for history

# Track temp files for cleanup on unexpected exit
NETRC_FILE=""
cleanup() {
    [ -n "$NETRC_FILE" ] && rm -f "$NETRC_FILE"
}
trap cleanup EXIT INT TERM

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

# Download image with retry logic
download_image() {
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        log "Downloading image from $INPUT_IP_ADDRESS (attempt $attempt/$MAX_RETRIES)"

        if wget "$INPUT_IP_ADDRESS" \
            --header 'Cookie: allow-download=1' \
            --timeout=$TIMEOUT \
            --tries=1 \
            -O "$IMAGE_PATH" \
            -q 2>/dev/null; then

            # Validate downloaded file
            if [ -f "$IMAGE_PATH" ]; then
                FILE_SIZE=$(stat -c%s "$IMAGE_PATH" 2>/dev/null || echo 0)

                if [ "$FILE_SIZE" -ge "$MIN_IMAGE_SIZE" ]; then
                    # Verify it's actually an image file
                    FILE_TYPE=$(file -b --mime-type "$IMAGE_PATH" 2>/dev/null || echo "unknown")

                    if echo "$FILE_TYPE" | grep -q "image/"; then
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

        if [ $attempt -lt $MAX_RETRIES ]; then
            log "Waiting $RETRY_DELAY seconds before retry..."
            sleep $RETRY_DELAY
        fi

        attempt=$((attempt + 1))
    done

    log_error "Failed to download image after $MAX_RETRIES attempts"
    return 1
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

# Main execution
log "=== Starting Ambient Weather Webcam Upload ==="
log "Server: $SERVER:$PORT"
log "Webcam: $INPUT_IP_ADDRESS"

# Cleanup old archived images
cleanup_old_images

# Download image
if ! download_image; then
    log_error "Script failed: Could not download image"
    exit 1
fi

# Upload image
if ! upload_image; then
    log_error "Script failed: Could not upload image"
    exit 1
fi

log "=== Upload completed successfully ==="
exit 0
