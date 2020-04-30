#!/bin/bash
set -e

echo "Creating mountpoints /p1 /p2"
mkdir /p1 /p2
disk=$(lsblk -dno name -e1,7,11 | sed 's|^|/dev/|' | sort)

echo "Mounting boot partition ${disk}p1"
mount ${disk}p1 /p1 
echo "Enabling ssh at boot time"
touch /p1/ssh && umount /p1

echo "Mounting root partition ${disk}p2"
mount ${disk}p2 /p2
cp -f /configure-systemd.sh /p2 
echo "Configuring systemd on persisted system" 
if chroot /p2 /configure-systemd.sh $WIFI_SSID $WIFI_PSK $WIFI_COUNTRY
then
  echo "Configuration performed successfully"
else
  echo "Something went wrong"
  exit 1
fi

rm -f /p2/configure-systemd.sh && umount /p2

