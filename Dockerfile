# Use Alpine Linux as the base image
FROM alpine:latest

# Install required packages
RUN apk --no-cache add wget \
                        curl \
                        busybox-extras                         


# Add the ams-cam-upload.sh script to the image
RUN mkdir /home/root
COPY ams-cam-upload.sh /usr/local/bin/ams-cam-upload.sh

RUN ls -al /
# Add the entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/ams-cam-upload.sh /entrypoint.sh

# Run the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
