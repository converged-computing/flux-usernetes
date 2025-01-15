#!/bin/bash 

set -euo pipefail

export CONTAINER_ENGINE=docker

# This is a system level install
usernetes_root=/home/azureuser/usernetes
cd $usernetes_root

# This is for a worker
make up
make kubeadm-join
