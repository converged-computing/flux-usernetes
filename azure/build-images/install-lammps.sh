#!/bin/bash

set -eu pipefail

# Just for this
sudo apt-get update
sudo apt-get install -y clang-format ffmpeg

# Install a "bare metal" lammps
cd /opt
export DEBIAN_FRONTEND=noninteractive

# Note we install to /usr so can be found by all users
sudo git clone --depth 1 https://github.com/lammps/lammps.git /opt/lammps
sudo chown -R $USER /opt/lammps
cd /opt/lammps
# This is the commit I used
# git checkout 4b756e0b1c5b51dd5ccbfeb91203335cd44e461c
mkdir build
cd build
. /etc/profile

cmake ../cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr -DPKG_REAXFF=yes -DBUILD_MPI=yes -DPKG_OPT=yes -DFFT=FFTW3

# This is the vanilla command
# cmake ../cmake -D PKG_REAXFF=yes -D BUILD_MPI=yes -D PKG_OPT=yes
make
sudo make install

# install to /usr/bin
sudo cp ./lmp /usr/bin/

# examples are in:
# /opt/lammps/examples/reaxff/HNS
cp -R /opt/lammps/examples/reaxff/HNS /home/azureuser/lammps

# permissions
chown -R azureuser /home/azureuser/lammps
cd /home/azureuser
sudo rm -rf /opt/lammps
