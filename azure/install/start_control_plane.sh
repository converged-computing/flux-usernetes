#!/bin/bash 

set -euo pipefail

# The listing of ranks that don't include the control plane (e.g., 1, or 1-N)
ranks="${1}"

export CONTAINER_ENGINE=docker

# This is a system level install
usernetes_root=/home/azureuser/usernetes
cd $usernetes_root

# Start the control plane and generate the join-command
# This is how to get the external address, since internal addresses don't work
export HOST_IP=$(curl -s https://api.ipify.org)
echo "Host external ip is ${HOST_IP}"
HOST_IP=$HOST_IP make up
sleep 5
HOST_IP=$HOST_IP make kubeadm-init
sleep 5
HOST_IP=$HOST_IP make install-flannel
HOST_IP=$HOST_IP make kubeconfig
HOST_IP=$HOST_IP make join-command

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
