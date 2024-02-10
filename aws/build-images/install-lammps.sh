#!/bin/bash

set -eu pipefail

# Install a "bare metal" lammps
cd /opt
export DEBIAN_FRONTEND=noninteractive

# Note we install to /usr so can be found by all users
git clone --depth 1 --branch stable_29Sep2021_update2 https://github.com/lammps/lammps.git /opt/lammps
cd /opt/lammps
mkdir build
cd build
. /etc/profile

# Ensure we target mpi from efa installer (I think that is hooked into libfabric?)
cmake ../cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr -DPKG_REAXFF=yes -DBUILD_MPI=yes -DPKG_OPT=yes -DFFT=FFTW3 -DCMAKE_PREFIX_PATH=/opt/amazon/openmpi -DCMAKE_PREFIX_PATH=/opt/amazon/efa

# This is the vanilla command
# cmake ../cmake -D PKG_REAXFF=yes -D BUILD_MPI=yes -D PKG_OPT=yes
make
sudo make install

# - Please logout/login to complete the installation.
# - Libfabric was installed in /opt/amazon/efa
# - Open MPI was installed in /opt/amazon/openmpi

# install to /usr/bin
sudo mv ./lmp /usr/bin/

# examples are in:
# /opt/lammps/examples/reaxff/HNS
cp -R /opt/lammps/examples/reaxff/HNS /home/ubuntu/lammps

# clean up
rm -rf /opt/lammps

# permissions
chown -R ubuntu /home/ubuntu/lammps

# Might need
# fi_info -p efa -t FI_EP_RDM
# Disable ptrace
# sysctl -w kernel.yama.ptrace_scope=0