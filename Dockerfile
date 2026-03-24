# Use Alpine Linux as the base image
FROM alpine:latest

# Install required packages
RUN apk --no-cache add wget \
                        curl \
                        busybox-extras \
                        file \
                        tzdata \
                        logrotate

# Create necessary directories
RUN mkdir -p /home/root/archive /var/log

# Copy scripts to the image
COPY ams-cam-upload.sh /usr/local/bin/ams-cam-upload.sh
COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY logrotate.conf /etc/logrotate.d/ams-cam-upload

# Make scripts executable
RUN chmod +x /usr/local/bin/ams-cam-upload.sh /entrypoint.sh /usr/local/bin/healthcheck.sh

# Health check configuration
HEALTHCHECK --interval=2m --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Run the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
