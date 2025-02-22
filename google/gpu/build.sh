#!/bin/bash

set -euo pipefail

################################################################
#
# Usernetes, and ORAS
# This was done on a new ubuntu 24.04 image on Google Cloud

# Note that I had to build this manually to install the gpu drivers and I
# used debian 11 ML image on Google Cloud, with CUDA 12.1. I am trying a newer OS 
# because that setup was not consistent

# Add our public key to ubuntu to ssh in.
mkdir -p ~/.ssh
echo "<YOUR PUBLIC KEY HERE>" >> ~/.ssh/authorized_keys

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && \
    sudo apt-get install -y apt-transport-https ca-certificates curl jq apt-utils wget make \
         python3-pip git net-tools build-essential

# Drivers

wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-8
sudo apt-get install -y cuda-drivers
curl -L https://github.com/GoogleCloudPlatform/compute-gpu-installation/releases/download/cuda-installer-v1.2.0/cuda_installer.pyz --output cuda_installer.pyz
sudo python3 cuda_installer.pyz install_driver
sudo python3 cuda_installer.pyz install_cuda
# Reboot
sudo python3 cuda_installer.pyz verify_cuda

# Install oras
cd /tmp
export ARCH=x86_64
export ORAS_ARCH=amd64
export VERSION="1.1.0" && \
curl -LO "https://github.com/oras-project/oras/releases/download/v${VERSION}/oras_${VERSION}_linux_${ORAS_ARCH}.tar.gz" && \
mkdir -p oras-install/ && \
tar -zxf oras_${VERSION}_*.tar.gz -C oras-install/ && \
sudo mv oras-install/oras /usr/local/bin/ && \
rm -rf oras_${VERSION}_*.tar.gz oras-install/

# Install Usernetes
echo "START updating cgroups2"
cat /etc/default/grub | grep GRUB_CMDLINE_LINUX=
GRUB_CMDLINE_LINUX=""
sudo sed -i -e 's/^GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"/' /etc/default/grub
sudo update-grub

sudo mkdir -p /etc/systemd/system/user@.service.d
cat <<EOF | tee delegate.conf
[Service]
Delegate=cpu cpuset io memory pids
EOF
sudo mv ./delegate.conf /etc/systemd/system/user@.service.d/delegate.conf

sudo systemctl daemon-reload
echo "DONE updating cgroups2"

echo "START updating kernel modules"
sudo modprobe ip_tables
tee ./usernetes.conf <<EOF >/dev/null
br_netfilter
vxlan
EOF

sudo mv ./usernetes.conf /etc/modules-load.d/usernetes.conf
sudo systemctl restart systemd-modules-load.service
echo "DONE updating kernel modules"

echo "START 99-usernetes.conf"
echo "net.ipv4.conf.default.rp_filter = 2" > /tmp/99-usernetes.conf
sudo mv /tmp/99-usernetes.conf /etc/sysctl.d/99-usernetes.conf
sudo sysctl --system
echo "DONE 99-usernetes.conf"

echo "START modprobe"
sudo modprobe vxlan
sudo systemctl daemon-reload

# https://github.com/rootless-containers/rootlesskit/blob/master/docs/port.md#exposing-privileged-ports
cp /etc/sysctl.conf ./sysctl.conf
echo "net.ipv4.ip_unprivileged_port_start=0" | tee -a ./sysctl.conf
echo "net.ipv4.conf.default.rp_filter=2" | tee -a ./sysctl.conf
sudo mv ./sysctl.conf /etc/sysctl.conf

sudo sysctl -p
sudo systemctl daemon-reload
echo "DONE modprobe"

echo "START kubectl"
cd /tmp
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ORAS_ARCH}/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/bin/kubectl
echo "DONE kubectl"

sudo apt-get install -y uidmap

sudo modprobe ip6_tables
sudo modprobe ip6table_nat
sudo modprobe iptable_nat

echo "Installing docker"
curl -o install.sh -fsSL https://get.docker.com
chmod +x install.sh
sudo ./install.sh
echo "done installing docker"

# GPU won't work with rootless unless we use CDI
# https://github.com/NVIDIA/libnvidia-container/issues/154
# sudo systemctl disable --now docker.service docker.socket
# would need to reboot but we can't
dockerd-rootless-setuptool.sh install
echo "export XDG_RUNTIME_DIR=/home/ubuntu/.docker/run" >> ~/.bashrc
echo "export DOCKER_HOST=unix:///run/user/1000/docker.sock" >> ~/.bashrc

export XDG_RUNTIME_DIR=/home/ubuntu/.docker/run
export PATH=/usr/bin:$PATH
export DOCKER_HOST=unix:///run/user/1000/docker.sock
mkdir -p $XDG_RUNTIME_DIR

echo "Installing docker user"
sudo loginctl enable-linger $USER
ls /var/lib/systemd/linger
# mkdir -p ~/.docker/run

systemctl --user enable docker.service
systemctl --user start docker.service

echo "Setting up usernetes"

# Write scripts to start control plane and worker nodes
# Clone usernetes and usernetes-python
sudo git clone https://github.com/rootless-containers/usernetes /opt/usernetes
sudo chown -R ubuntu /opt/usernetes
sudo chown -R $USER /opt/usernetes 
# git clone https://github.com/converged-computing/usernetes-python ~/usernetes-python
cd /opt/usernetes

# Memory / file limits
cat <<EOF | tee /tmp/memory
*	soft	nproc	unlimited
*	hard	nproc	unlimited
*	soft	memlock	unlimited
*	hard	memlock	unlimited
*	soft	stack	unlimited
*	hard	stack	unlimited
*	soft	nofile	unlimited
*	hard	nofile	unlimited
*	soft	cpu	unlimited
*	hard	cpu	unlimited
*	soft	rtprio	unlimited
*	hard	rtprio	unlimited
EOF

sudo cp /tmp/memory /etc/security/limits.d/98-google-hpc-image.conf
sudo cp /tmp/memory /etc/security/limits.conf

# Install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3     && chmod 700 get_helm.sh && ./get_helm.sh
 
# Don't forget to add entries to /etc/systemd/system.conf and /etc/systemd/user.conf and /etc/security/limits.conf for MEMLOCK and NPROC (in the first, should be infinity, in the second security should be unlimited) 
# *                soft    nproc           unlimited
# *                hard    nproc           unlimited
# *                soft    nofile          unlimited
# *                hard    nofile          unlimited
# but without comments, of course!

export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/cloud.google.asc
sudo apt-get update
sudo apt-get install -y gcsfuse libfuse-dev

# IMPORTANT! The last line of /usr/bin/dockerd-rootless.sh needs to be
# exec "$dockerd" "--config-file"	"/etc/docker/daemon.json" "$@"
# with the condig file, otherwise you won't find the nvidia runtime

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Also uncomment line about envvars at top here:
# the top two lines of this file /etc/nvidia-container-runtime/config.toml

sudo nvidia-ctk runtime configure --runtime=docker --cdi.enabled --config=/etc/docker/daemon.json
# This should be run when gpus are allocated - they have specific ids
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid
nvidia-ctk cdi list
sudo nvidia-ctk config --in-place --set nvidia-container-runtime.mode=cdi
systemctl restart --user docker.service

# pssh
sudo python3 -m pip install pssh --break-system-packages

# 
# At this point we have what we need!

