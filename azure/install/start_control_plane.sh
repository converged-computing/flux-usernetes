#!/bin/bash 

set -euo pipefail

# The listing of ranks that don't include the control plane (e.g., 1, or 1-N)
ranks="${1}"

export CONTAINER_ENGINE=docker

# This is a system level install
usernetes_root=/home/azureuser/usernetes
cd $usernetes_root

make up
sleep 5
make kubeadm-init
sleep 5
make install-flannel
make kubeconfig
make join-command

# Share the join-command with the workers
flux archive create --name join-command --directory $usernetes_root join-command
flux exec -x 0 -r ${ranks} flux archive extract --name join-command --directory $usernetes_root
flux archive remove --name join-command

echo "export KUBECONFIG=/home/azureuser/usernetes/kubeconfig" >> /home/azureuser/.bashrc
export KUBECONFIG=/home/azureuser/usernetes/kubeconfig
echo "Waiting 5 seconds for control plane to be ready..."
sleep 5
kubectl get nodes

# 
# At this point we have what we need!
