#!/bin/bash
set -e 
secret=$1
url=$2
if [[ -n $1 && -z $2 ]]
then
 curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true K3S_CLUSTER_SECRET=${secret} sh - || echo "k8s master installed"
else
 curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true K3S_CLUSTER_SECRET=${secret} K3S_URL=${url} sh - || echo "k8s node installed"
fi

