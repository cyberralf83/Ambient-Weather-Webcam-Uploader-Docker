#!/bin/bash


wget 'http://192.168.1.120/action/snap?cam=0&user=admin&pwd=12345' --header 'Cookie: allow-download=1' -O image.jpg 
wput ftp://CC50E3D11817:b469dd76@ftp.ambientweather.net image.jpg



#Then chmod +x ambientweather.sh
#run via: ./ambientweather.sh