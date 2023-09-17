#!/bin/sh
# Create a cron job to run webcamio.sh every two minutes
./usr/local/bin/ams-cam-upload.sh
echo "*/2 * * * * /usr/local/bin/ams-cam-upload.sh" >> /etc/crontabs/root
# Run cron in the foreground
crond -f
