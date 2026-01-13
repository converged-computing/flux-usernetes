#!/bin/bash 

set -euo pipefail

export CONTAINER_ENGINE=docker

# This is a system level install
usernetes_root=/home/azureuser/usernetes
cd $usernetes_root

# Go to town!
make sync-external-ip
export KUBECONFIG=/home/azureuser/usernetes/kubeconfig
kubectl get nodes
