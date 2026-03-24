#!/bin/sh

echo "The value of INPUT_IP_ADDRESS is $INPUT_IP_ADDRESS"
echo "The value of SERVER is $SERVER"
echo "The value of PORT is $PORT"
echo "The value of USERNAME is $USERNAME"
echo "The value of PASSWORD is ${PASSWORD:+[SET]}${PASSWORD:-[NOT SET]}"
