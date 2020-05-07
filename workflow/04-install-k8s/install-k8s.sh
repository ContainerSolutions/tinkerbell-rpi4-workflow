#!/bin/bash
set -e
echo "Creating mountpoint /p2"
mkdir /p2
disk=$(lsblk -dno name -e1,7,11 | sed 's|^|/dev/|' | sort)

echo "Mounting root partition ${disk}p2"
mount ${disk}p2 /p2 

echo "Executing k8s setup script"
cp -f setup-k8s.sh /p2

echo "Gathering info from hegel $HEGEL_URL"

HOSTNAME=$(curl -s ${HEGEL_URL}/metadata | jq -r .hostname)
IP=${NODE_IP}

chroot /p2 /setup-k8s.sh "$IP" "$HOSTNAME" "$K8S_CLUSTER_SECRET" $K3S_URL
echo "Cleaning up" 
rm -f /p2/setup-k8s.sh
umount /p2

