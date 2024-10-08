#!/bin/bash 

# This startup script installs usernetes and prepares the environment / node for that

set -euo pipefail

cd /tmp
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

# I'm sure this is a very bad idea
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
#curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/bin/kubectl
echo "DONE kubectl"

# docker is already installed, so will give warning
echo "Installing docker"
curl -o install.sh -fsSL https://get.docker.com
chmod +x install.sh
sudo ./install.sh
echo "done installing docker"

# Note that broker.toml is written in the startup script now
# Along with the /etc/flux/system/R
sudo mkdir -p /etc/flux/system

sudo chown -R azureuser /home/azureuser
echo "Setting up usernetes"

echo "export PATH=/usr/bin:$PATH" >> ~/.bashrc
echo "export XDG_RUNTIME_DIR=/home/azureuser/.docker/run" >> ~/.bashrc
# This wants to write into run, which is probably OK (under userid)
echo "export DOCKER_HOST=unix:///home/azureuser/.docker/run/docker.sock" >> ~/.bashrc

echo "Installing docker user"
sudo loginctl enable-linger azureuser

ls /var/lib/systemd/linger

# ensure these are set
# . /home/azureuser/.bashrc
# export DOCKER_HOST=unix:///home/azureuser/.docker/run/docker.sock
# export XDG_RUNTIME_DIR=/home/azureuser/.docker/run
mkdir -p /home/azureuser/.docker/run

# This might show failure because it creates the docker.sock in /run/user/UID/docker.sock
# but then we link to the expected path below
dockerd-rootless-setuptool.sh install
sleep 10
systemctl --user enable docker.service
systemctl --user start docker.service

# Not sure why this is happening, but it's starting here
# As long as docker run hello world works we are good!
ln -s /run/user/1000/docker.sock /home/azureuser/.docker/run/docker.sock
docker run hello-world

# Write scripts to start control plane and worker nodes

# Clone usernetes, and also wget the scripts to start control plane and worker nodes
if [[ ! -d "/home/azureuser/usernetes" ]]; then
    git clone --depth 1 https://github.com/rootless-containers/usernetes ~/usernetes
fi
cd ~/usernetes
echo "Usernetes is in ~/usernetes"

if [ ! -f "start-control-plane.sh" ]; then
cat <<EOF | tee ./start-control-plane.sh
#!/bin/bash

# Go to usernetes home
cd ~/usernetes

# This is logic for the lead broker (we assume this one)
make up

sleep 10
make kubeadm-init
sleep 5
make install-flannel
make kubeconfig
export KUBECONFIG=/home/ubuntu/usernetes/kubeconfig
make join-command

# IMPORTANT: This needs to be run on control plane after the workers join
# make sync-external-ip
echo "export KUBECONFIG=/home/azureuser/usernetes/kubeconfig" >> ~/.bashrc
EOF
chmod +x ./start-control-plane.sh
fi

if [ ! -f "start-worker.sh" ]; then
cat <<EOF | tee ./start-worker.sh
#!/bin/bash

# Go to usernetes home
cd ~/usernetes

make up
sleep 5

# This assumes join-command is already here
make kubeadm-join
EOF
chmod +x ./start-worker.sh
fi

echo "Done installing docker user"
sudo chown azureuser /etc/flux/system/curve.cert
sudo chown -R azureuser /home/azureuser
