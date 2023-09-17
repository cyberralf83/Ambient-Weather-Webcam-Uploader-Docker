#!/bin/sh
set -x

echo "The value of SERVER is $SERVER"

wget $INPUT_IP_ADDRESS --header 'Cookie: allow-download=1' -O /home/root/image.jpg 

sleep 2 
ls -l /home/root/image.jpg

curl -T /home/root/image.jpg -u "$USERNAME:$PASSWORD" "ftp://$SERVER:$PORT/"

