#!/bin/bash

set -eu pipefail

# Just for this
sudo apt-get install -y clang-format ffmpeg

# Install a "bare metal" lammps
cd /opt
export DEBIAN_FRONTEND=noninteractive

# Note we install to /usr so can be found by all users
git clone --depth 1 https://github.com/lammps/lammps.git /opt/lammps
cd /opt/lammps
# This is the commit I used
# git checkout e299e4967d18ee1a79710dcff2a13b1ef0f03d35
mkdir build
cd build
. /etc/profile

# we MUST use openmpi...
# sudo apt-get install openmpi-bin openmpi-doc libopenmpi-dev 

# Sanity check we aren't using AWS MPI!
# export PATH=/usr/bin:/usr/local/go/bin:/opt/amazon/efa/bin:/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
# export LD_LIBRARY_PATH=/opt/amazon/efa/lib

# Ensure we target mpi from efa installer (I think that is hooked into libfabric?)
# Note you should NOT install using the aws MPI it WILL NOT WORK
cmake ../cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr -DPKG_REAXFF=yes -DBUILD_MPI=yes -DPKG_OPT=yes -DFFT=FFTW3 -DCMAKE_PREFIX_PATH=/opt/amazon/efa -DCMAKE_PREFIX_PATH=/opt/amazon/openmpi5

# This is the vanilla command
# cmake ../cmake -D PKG_REAXFF=yes -D BUILD_MPI=yes -D PKG_OPT=yes
make
sudo make install

# - Please logout/login to complete the installation.
# - Libfabric was installed in /opt/amazon/efa
# - Open MPI was installed in /opt/amazon/openmpi

# install to /usr/bin
sudo cp ./lmp /usr/bin/

# examples are in:
# /opt/lammps/examples/reaxff/HNS
cp -R /opt/lammps/examples/reaxff/HNS /home/ubuntu/lammps

# clean up (nah)
# rm -rf /opt/lammps

# permissions
chown -R ubuntu /home/ubuntu/lammps
