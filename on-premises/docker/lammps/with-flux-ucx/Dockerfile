FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# docker build -t ghcr.io/converged-computing/usernetes-python:lammps-flux-infiniband-openmpi-ucx .

RUN apt-get update && apt-get install -y build-essential \
    tar \
    autoconf \
    automake \
    make \
    wget \
    git \
    gcc \
    g++ \
    zip \
    cmake \
    libblas-dev \
    liblapack-dev \
    fftw3-dev fftw3 \
    libxml2 \
    libxml2-dev \
    hdf5-tools \
    libhdf5-dev \
    libboost-all-dev \
    && apt-get clean

# Utilities
RUN apt-get update && \
    apt-get -qq install -y --no-install-recommends \
        apt-utils \
        locales \
        ca-certificates \
        wget \
        man \
        git \
        flex \
        ssh \
        sudo \
        vim \
        luarocks \
        munge \
        lcov \
        ccache \
        lua5.2 \
        python3-dev \
        python3-pip \
        valgrind \
        jq && \
    rm -rf /var/lib/apt/lists/*

# Compilers, autotools
RUN apt-get update && \
    apt-get -qq install -y --no-install-recommends \
        build-essential \
        pkg-config \
        autotools-dev \
        libtool \
	libffi-dev \
        autoconf \
        automake \
        make \
        clang \
        clang-tidy \
        gcc \
        g++ && \
    rm -rf /var/lib/apt/lists/*

# Python - instead of a system python we install anaconda
# https://docs.conda.io/en/latest/miniconda.html#linux-installers
RUN pip install --upgrade --ignore-installed \
        "markupsafe==2.0.0" \
        coverage cffi ply six pyyaml "jsonschema>=2.6,<4.0" \
        sphinx sphinx-rtd-theme sphinxcontrib-spelling 
        
RUN apt-get update && \
    apt-get -qq install -y --no-install-recommends \
        libsodium-dev \
        libzmq3-dev \
        libczmq-dev \
        libjansson-dev \
        libmunge-dev \
        libncursesw5-dev \
        liblua5.2-dev \
        liblz4-dev \
        libsqlite3-dev \
        uuid-dev \
        libhwloc-dev \
        libs3-dev \
        libevent-dev \
        libarchive-dev \
        libpam-dev && \
    rm -rf /var/lib/apt/lists/*

# Testing utils and libs
RUN apt-get update && \
    apt-get -qq install -y --no-install-recommends \
        faketime \
        libfaketime \
        pylint \
        cppcheck \
        enchant-2 \
        aspell \
        aspell-en && \
    rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8

# NOTE: luaposix installed by rocks due to Ubuntu bug: #1752082 https://bugs.launchpad.net/ubuntu/+source/lua-posix/+bug/1752082
RUN luarocks install luaposix

# Install openpmix, prrte
WORKDIR /opt/prrte
RUN git clone https://github.com/openpmix/openpmix.git && \
    git clone https://github.com/openpmix/prrte.git && \
    ls -l && \
    set -x && \
    cd openpmix && \
    git checkout fefaed568f33bf86f28afb6e45237f1ec5e4de93 && \
    ./autogen.pl && \
    ./configure --prefix=/usr --disable-static && make -j 4 install && \
    ldconfig && \
    cd .. && \
    cd prrte && \
    git checkout 477894f4720d822b15cab56eee7665107832921c && \
    ./autogen.pl && \
    ./configure --prefix=/usr && make -j 4 install && \
    cd ../.. && \
    rm -rf prrte

ENV LANG=C.UTF-8
ARG FLUX_SECURITY_VERSION=0.11.0

WORKDIR /opt
RUN CCACHE_DISABLE=1 && \
    V=$FLUX_SECURITY_VERSION && \
    PKG=flux-security-$V && \
    URL=https://github.com/flux-framework/flux-security/releases/download && \
    wget ${URL}/v${V}/${PKG}.tar.gz && \
    tar xvfz ${PKG}.tar.gz && \
    cd ${PKG} && \
    ./configure --prefix=/usr --sysconfdir=/etc || cat config.log && \
    make -j 4 && \
    make install && \
    cd .. && \
    rm -rf flux-security-*

# Setup MUNGE directories & key
RUN mkdir -p /var/run/munge && \
    dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key && \
    chown -R munge /etc/munge/munge.key /var/run/munge && \
    chmod 600 /etc/munge/munge.key

RUN wget https://github.com/flux-framework/flux-core/releases/download/v0.61.2/flux-core-0.61.2.tar.gz && \
    tar xzvf flux-core-0.61.2.tar.gz && \
    cd flux-core-0.61.2 && \
    ./configure --prefix=/usr --sysconfdir=/etc && \
    make clean && \
    make && \
    sudo make install

RUN sudo apt-get update
RUN sudo apt-get -qq install -y --no-install-recommends \
	libboost-graph-dev \
	libboost-system-dev \
	libboost-filesystem-dev \
	libboost-regex-dev \
	libyaml-cpp-dev \
	libedit-dev \
        libboost-dev \
        libyaml-cpp-dev \
	curl

ENV LD_LIBRARY_PATH=/opt/miniconda/lib
    
RUN wget https://github.com/flux-framework/flux-sched/releases/download/v0.33.1/flux-sched-0.33.1.tar.gz && \
    tar -xzvf flux-sched-0.33.1.tar.gz && \
    cd flux-sched-0.33.1 && \
    ./configure --prefix=/usr --sysconfdir=/etc && \
    make && \
    sudo make install && \
    ldconfig

RUN apt-get update && \
    apt-get install -y fftw3-dev fftw3 pdsh libfabric-dev libfabric1 \
        openssh-client openssh-server \
        dnsutils telnet strace git g++ \
        unzip bzip2

RUN apt-get update && \
    apt-get install -y fftw3-dev fftw3 pdsh libfabric-dev libfabric1 \
        openssh-client openssh-server \
        dnsutils telnet strace git g++ \
        unzip bzip2

WORKDIR /opt

# Install oras for saving artifacts
RUN export VERSION="1.2.0" && \
    curl -LO "https://github.com/oras-project/oras/releases/download/v${VERSION}/oras_${VERSION}_linux_amd64.tar.gz" && \
    mkdir -p oras-install/ && \
    tar -zxf oras_${VERSION}_*.tar.gz -C oras-install/ && \
    mv oras-install/oras /usr/local/bin/ && \
    rm -rf oras_${VERSION}_*.tar.gz oras-install/
    
# Additional packages
RUN apt-get update && apt-get install -y ibverbs-utils libibverbs-dev libibverbs1 && apt-get clean

ARG LAMMPS_VERSION="stable_2Aug2023" 
ARG UCX_VERSION="1.17.0"

# Install essential build tools and libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    dnsutils telnet strace cmake git g++ iputils-ping \
    build-essential \
    cmake \
    gfortran \
    git \
    wget \
    ca-certificates \
    libibverbs-dev \
    librdmacm-dev \
    libnuma-dev \
    libfftw3-dev \
    libfftw3-mpi-dev \
    python3-dev \
    libibumad-dev \    
    pkg-config \
    rdma-core \
    yacc \
    libcap-dev \
&& rm -rf /var/lib/apt/lists/*


# --- Install UCX ---
WORKDIR /tmp
RUN wget "https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz" && \
    tar -xzf "ucx-${UCX_VERSION}.tar.gz" && \
    cd "ucx-${UCX_VERSION}" && \
    ./configure --prefix=/opt/ucx --enable-optimizations --with-verbs --with-rdmacm --enable-cma --with-rc --with-ud --with-dc --with-mlx5-dv \
    && make -j$(nproc) && \
    make install && \
    cd /tmp && \
    rm -rf "ucx-${UCX_VERSION}"

# --- Install OpenMPI with UCX -
ENV PATH="/opt/ucx/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/ucx/lib:${LD_LIBRARY_PATH}" \
    PKG_CONFIG_PATH="/opt/ucx/lib/pkgconfig:${PKG_CONFIG_PATH}"

WORKDIR /opt
RUN wget https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-4.1.2.tar.gz && \
    tar -xzvf openmpi-4.1.2.tar.gz && \
    cd openmpi-4.1.2 && \
    ./configure --with-ucx --without-verbs --prefix=/usr && \
    make && make install

# --- Install LAMMPS ---
WORKDIR /opt
RUN wget "https://github.com/lammps/lammps/archive/refs/tags/${LAMMPS_VERSION}.tar.gz" -O lammps.tar.gz && \
    tar -xzf lammps.tar.gz && \
    mv lammps-${LAMMPS_VERSION} lammps && \
    rm lammps.tar.gz

ENV LD_LIBRARY_PATH="/usr/lib:${LD_LIBRARY_PATH}"
ENV MPICC="/usr/bin/mpicc"
ENV MPICXX="/usr/bin/mpicxx"
ENV MPIF90="/usr/bin/mpif90"

WORKDIR /opt/lammps
RUN mkdir build && cd build && \
    cmake ../cmake \
    -D CMAKE_BUILD_TYPE=Release \
    -D BUILD_MPI=yes \
    -D BUILD_SHARED_LIBS=yes \
    -D LAMMPS_EXCEPTIONS=yes \
    -D CMAKE_INSTALL_PREFIX:PATH=/usr \
    -DPKG_REAXFF=yes \ 
    -DPKG_OPT=yes \
    -DFFT=FFTW3 \
    -D PKG_MOLECULE=yes \
    -D PKG_KSPACE=yes \
    -D PKG_MANYBODY=yes \
    -D PKG_RIGID=yes \
    && make -j4 && \
    make install && \
    rm -rf /tmp/lammps_source

RUN apt-get update && apt-get install -y net-tools ibverbs-utils ibutils
WORKDIR /opt/lammps/examples/reaxff/HNS


