#!/bin/bash
set -e
mkdir -p /run/systemd

echo "Disabling eeprom overwrite"
systemctl disable rpi-eeprom-update.service
systemctl disable bluetooth

hostname=$1

if [[ -n $hostname ]] ;then
  echo "Setting hostname to ${hostname}" 
  echo $hostname > /etc/hostname
  sed -i "s%127.0.1.1.*%127.0.1.1\t${hostname}%g" /etc/hosts
fi

ssid=$2
psk=$3
country=$4

if [[ -n $ssid || -n $psk || -n $country ]]; then
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
