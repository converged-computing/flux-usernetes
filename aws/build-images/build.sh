#!/bin/bash

set -euo pipefail

################################################################
#
# Flux, Singularity, and EFA
#

/usr/bin/cloud-init status --wait

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && \
    sudo apt-get install -y apt-transport-https ca-certificates curl jq apt-utils wget \
         libelf-dev libpcap-dev libbfd-dev binutils-dev build-essential make \
         linux-tools-common linux-tools-$(uname -r)  \
         python3-pip git net-tools

# cmake is needed for flux-sched, and make sure to choose arm or x86
export CMAKE=3.23.1
export ARCH=aarch64
export ORAS_ARCH=arm64

curl -s -L https://github.com/Kitware/CMake/releases/download/v$CMAKE/cmake-$CMAKE-linux-$ARCH.sh > cmake.sh && \
    sudo sh cmake.sh --prefix=/usr/local --skip-license && \
    sudo apt-get install -y man flex ssh sudo vim luarocks munge lcov ccache lua5.4 \
         valgrind build-essential pkg-config autotools-dev libtool \
         libffi-dev autoconf automake make clang clang-tidy \
         gcc g++ libpam-dev apt-utils lua-posix \
         libsodium-dev libzmq3-dev libczmq-dev libjansson-dev libmunge-dev \
         libncursesw5-dev liblua5.4-dev liblz4-dev libsqlite3-dev uuid-dev \
         libhwloc-dev libs3-dev libevent-dev libarchive-dev \
         libboost-graph-dev libboost-system-dev libboost-filesystem-dev \
         libboost-regex-dev libyaml-cpp-dev libedit-dev uidmap dbus-user-session python3-cffi

# Prepare lua rocks (does it really rock?)
sudo locale-gen en_US.UTF-8

# This is needed if you intend to use EFA (HPC instance type)
# Install EFA alone without AWS OPEN_MPI
# At the time of running this, latest was 1.32.0
export EFA_VERSION=latest
mkdir /tmp/efa 
cd /tmp/efa
curl -O https://s3-us-west-2.amazonaws.com/aws-efa-installer/aws-efa-installer-${EFA_VERSION}.tar.gz
tar -xf aws-efa-installer-${EFA_VERSION}.tar.gz
cd aws-efa-installer
sudo ./efa_installer.sh -y

# Disable ptrace
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html
sudo sysctl -w kernel.yama.ptrace_scope=0

################################################################
## Install Flux and dependencies
#
sudo chown -R $USER /opt && \
    mkdir -p /opt/prrte && \
    cd /opt/prrte && \
    git clone https://github.com/openpmix/openpmix.git && \
    git clone https://github.com/openpmix/prrte.git && \
    cd openpmix && \
    git checkout fefaed568f33bf86f28afb6e45237f1ec5e4de93 && \
    ./autogen.pl && \
    ./configure --prefix=/usr --disable-static && sudo make install && \
    sudo ldconfig


# prrte you are sure looking perrrty today
cd /opt/prrte/prrte && \
    git checkout 477894f4720d822b15cab56eee7665107832921c && \
    ./autogen.pl && \
    ./configure --prefix=/usr && sudo make -j install

# flux security
wget https://github.com/flux-framework/flux-security/releases/download/v0.11.0/flux-security-0.11.0.tar.gz && \
    tar -xzvf flux-security-0.11.0.tar.gz && \
    mv flux-security-0.11.0 /opt/flux-security && \
    cd /opt/flux-security && \
    ./configure --prefix=/usr --sysconfdir=/etc && \
    make -j && sudo make install

# The VMs will share the same munge key
sudo mkdir -p /var/run/munge && \
    dd if=/dev/urandom bs=1 count=1024 > munge.key && \
    sudo mv munge.key /etc/munge/munge.key && \
    sudo chown -R munge /etc/munge/munge.key /var/run/munge && \
    sudo chmod 600 /etc/munge/munge.key

# Make the flux run directory
mkdir -p /home/ubuntu/run/flux

# Flux core
wget https://github.com/flux-framework/flux-core/releases/download/v0.66.0/flux-core-0.66.0.tar.gz && \
    tar -xzvf flux-core-0.66.0.tar.gz && \
    mv flux-core-0.66.0 /opt/flux-core && \
    cd /opt/flux-core && \
    ./configure --prefix=/usr --sysconfdir=/etc --runstatedir=/home/flux/run --with-flux-security && \
    make clean && \
    make -j && sudo make install

# Flux pmix (must be installed after flux core)
wget https://github.com/flux-framework/flux-pmix/releases/download/v0.5.0/flux-pmix-0.5.0.tar.gz && \
    tar -xzvf flux-pmix-0.5.0.tar.gz && \
    mv flux-pmix-0.5.0 /opt/flux-pmix && \
    cd /opt/flux-pmix && \
    ./configure --prefix=/usr && \
    make -j && \
    sudo make install

# Flux sched
wget https://github.com/flux-framework/flux-sched/releases/download/v0.37.0/flux-sched-0.37.0.tar.gz && \
    tar -xzvf flux-sched-0.37.0.tar.gz && \
    mv flux-sched-0.37.0 /opt/flux-sched && \
    cd /opt/flux-sched && \
    mkdir build && \
    cd build && \
    cmake ../ && make -j && sudo make install && sudo ldconfig && \
    echo "DONE flux build"

# Flux curve.cert
# Ensure we have a shared curve certificate
flux keygen /tmp/curve.cert && \
    sudo mkdir -p /etc/flux/system && \
    sudo cp /tmp/curve.cert /etc/flux/system/curve.cert && \
    sudo chown ubuntu /etc/flux/system/curve.cert && \
    sudo chmod o-r /etc/flux/system/curve.cert && \
    sudo chmod g-r /etc/flux/system/curve.cert && \
    # Permissions for imp
    sudo chmod u+s /usr/libexec/flux/flux-imp && \
    sudo chmod 4755 /usr/libexec/flux/flux-imp && \
    # /var/lib/flux needs to be owned by the instance owner
    sudo mkdir -p /var/lib/flux && \
    sudo chown $USER -R /var/lib/flux && \
    # clean up (and make space)
    cd /opt
    sudo rm -rf /opt/flux-core /opt/flux-sched /opt/prrte /opt/flux-security /opt/flux-pmix

# Install oras and singularity
export VERSION="1.1.0" && \
curl -LO "https://github.com/oras-project/oras/releases/download/v${VERSION}/oras_${VERSION}_linux_${ORAS_ARCH}.tar.gz" && \
mkdir -p oras-install/ && \
tar -zxf oras_${VERSION}_*.tar.gz -C oras-install/ && \
sudo mv oras-install/oras /usr/local/bin/ && \
rm -rf oras_${VERSION}_*.tar.gz oras-install/

cd /opt

# flux start mpirun -n 6 singularity exec singularity-mpi_mpich.sif /opt/mpitest
sudo apt-get update && sudo apt-get install -y libseccomp-dev libglib2.0-dev cryptsetup \
   libfuse-dev \
   squashfs-tools \
   squashfs-tools-ng \
   uidmap \
   zlib1g-dev \
   iperf3

sudo apt-get install -y \
   autoconf \
   automake \
   cryptsetup \
   git \
   libfuse-dev \
   libglib2.0-dev \
   libseccomp-dev \
   libtool \
   pkg-config \
   runc \
   squashfs-tools \
   squashfs-tools-ng \
   uidmap \
   wget \
   zlib1g-dev

# install go
wget https://go.dev/dl/go1.21.0.linux-${ORAS_ARCH}.tar.gz
tar -xvf go1.21.0.linux-${ORAS_ARCH}.tar.gz
sudo mv go /usr/local && rm go1.21.0.linux-${ORAS_ARCH}.tar.gz
export PATH=/usr/local/go/bin:$PATH

# Install singularity
export VERSION=4.0.1 && \
    wget https://github.com/sylabs/singularity/releases/download/v${VERSION}/singularity-ce-${VERSION}.tar.gz && \
    tar -xzf singularity-ce-${VERSION}.tar.gz && \
    cd singularity-ce-${VERSION}

./mconfig && \
 make -C builddir && \
 sudo make -C builddir install


# Just for this
sudo apt-get install -y clang-format ffmpeg

# Install a "bare metal" lammps
git clone --depth 1 https://github.com/lammps/lammps.git /opt/lammps
cd /opt/lammps
mkdir build
cd build
cmake ../cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr -DPKG_REAXFF=yes -DBUILD_MPI=yes -DPKG_OPT=yes -DFFT=FFTW3 -DCMAKE_PREFIX_PATH=/opt/amazon/efa -DCMAKE_PREFIX_PATH=/opt/amazon/openmpi
make
sudo make install
sudo cp ./lmp /usr/bin/
cp -R /opt/lammps/examples/reaxff/HNS /home/ubuntu/lammps

# Install Usernetes
cd /opt
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
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/bin/kubectl
echo "DONE kubectl"

echo "Installing docker"
curl -o install.sh -fsSL https://get.docker.com
chmod +x install.sh
sudo ./install.sh
echo "done installing docker"

# Note that broker.toml is written in the startup script now
# Along with the /etc/flux/system/R
sudo mkdir -p /etc/flux/system

# https://github.com/docker/docs/issues/14491
sudo apt install -y systemd-container

sudo chown -R ubuntu /home/ubuntu
echo "Setting up usernetes"
echo "export PATH=/usr/bin:$PATH" >> ~/.bashrc
echo "export XDG_RUNTIME_DIR=/home/ubuntu/.docker/run" >> ~/.bashrc
# This wants to write into run, which is probably OK (under userid)
echo "export DOCKER_HOST=unix:///home/ubuntu/.docker/run/docker.sock" >> ~/.bashrc

echo "Installing docker user"
sudo loginctl enable-linger ubuntu
ls /var/lib/systemd/linger
mkdir -p /home/ubuntu/.docker/run

# This might show failure because it creates the docker.sock in /run/user/UID/docker.sock
# but then we link to the expected path below
dockerd-rootless-setuptool.sh install || true
sleep 10
systemctl --user enable docker.service
systemctl --user start docker.service

# Not sure why this is happening, but it's starting here
# As long as docker run hello world works we are good!
ln -s /run/user/1000/docker.sock /home/ubuntu/.docker/run/docker.sock
docker run hello-world

# Write scripts to start control plane and worker nodes
# Clone usernetes and usernetes-python
git clone https://github.com/rootless-containers/usernetes ~/usernetes
git clone https://github.com/converged-computing/usernetes-python ~/usernetes-python
cd ~/usernetes-python
sudo python3 -m pip install -e .

echo "Done installing docker user"
sudo chown ubuntu /etc/flux/system/curve.cert
sudo chown -R ubuntu /home/ubuntu

# 
# At this point we have what we need!
