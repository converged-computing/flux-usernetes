#!/bin/bash 

set -euo pipefail

export CONTAINER_ENGINE=docker

# This is a system level install
usernetes_root=/home/azureuser/usernetes
cd $usernetes_root

# This is for a worker
export HOST_IP=$(curl -s https://api.ipify.org)
echo "Host external ip is ${HOST_IP}"

# Go to town!
make HOST_IP=$HOST_IP sync-external-ip
export KUBECONFIG=/home/azureuser/usernetes/kubeconfig
kubectl get nodes
