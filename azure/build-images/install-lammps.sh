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

# Without GPU
cmake ../cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr -DPKG_REAXFF=yes -DBUILD_MPI=yes -DPKG_OPT=yes -DFFT=FFTW3

# This is the vanilla command
# cmake ../cmake -D PKG_REAXFF=yes -D BUILD_MPI=yes -D PKG_OPT=yes
make
sudo make install

# With GPU
export PATH=$PATH:/opt/openmpi-4.1.5/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/openmpi-4.1.5/lib
cmake \
  -D CMAKE_INSTALL_PREFIX=/usr \
  -D CMAKE_BUILD_TYPE=Release \
  -D Kokkos_ARCH_VOLTA70=ON \
  -D MPI_CXX_COMPILER=mpicxx \
  -D BUILD_MPI=yes \
  -D CMAKE_CXX_COMPILER=$PWD/../lib/kokkos/bin/nvcc_wrapper \
  -D PKG_ML-SNAP=yes \
  -D PKG_GPU=no \
  -D PKG_REAXFF=on \
  -D PKG_KOKKOS=yes \
  -D Kokkos_ENABLE_CUDA=yes \
  ../cmake && make -j 20 && make install

# install to /usr/bin
sudo cp ./lmp /usr/bin/

# examples are in:
# /opt/lammps/examples/reaxff/HNS
cp -R /opt/lammps/examples/reaxff/HNS /home/azureuser/lammps

# permissions
chown -R azureuser /home/azureuser/lammps
cd /home/azureuser
sudo rm -rf /opt/lammps
