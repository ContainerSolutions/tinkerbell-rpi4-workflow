#!/bin/bash
set -e
set -x
ip=$1
hostname=$2
secret=$3
url=$4
export ARCH=armv7
if [[ -n $secret && -z $url ]]
then
 curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true K3S_CLUSTER_SECRET=${secret} INSTALL_K3S_EXEC="--bind-address=${ip} --advertise-address=${ip} --node-ip=${ip} --node-external-ip=${ip} --flannel-iface=eth0" K3S_NODE_NAME=${hostname} sh - || echo "k8s master installed"
else
 curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true K3S_CLUSTER_SECRET=${secret} K3S_URL=${url} INSTALL_K3S_EXEC="--node-ip=${ip} --node-external-ip=${ip} --flannel-iface=eth0" K3S_NODE_NAME=${hostname}  sh - || echo "k8s worker installed"
fi

