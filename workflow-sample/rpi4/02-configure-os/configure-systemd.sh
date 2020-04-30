#!/bin/bash
set -e
mkdir -p /run/systemd

echo "Disabling eeprom overwrite"
systemctl disable rpi-eeprom-update.service
systemctl disable bluetooth

ssid=$1
psk=$2
country=$3

if [[ -n $1 || -n $2 || -n $3 ]]; then
  echo 'Configuring wifi and wpa_supplicant'
  echo 0 > /var/lib/systemd/rfkill/platform-fe300000.mmcnr\:wlan
  rm -f  /var/lib/systemd/rfkill/platform-3f300000.mmcnr\:wlan
  cat << EOF  > /etc/wpa_supplicant/wpa_supplicant.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$country

network={
        ssid="$ssid"
        psk="$psk"
}
EOF

 systemctl enable wpa_supplicant
fi
