FROM ubuntu:22.04 as builder

# docker build -t ghcr.io/converged-computing/usernetes-python:osu-infiniband-openmpi .

# I'm keeping this here to avoid building new layers.
ARG LAMMPS_VERSION="stable_2Aug2023" 
ARG UCX_VERSION="1.17.0"

ENV DEBIAN_FRONTEND=noninteractive

# Install essential build tools and libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    dnsutils telnet strace cmake git g++ iputils-ping \
    build-essential \
    cmake \
    gfortran \
    git \
    wget \
    ca-certificates \
    # MVAPICH2 & InfiniBand dependencies
    libibverbs-dev \
    librdmacm-dev \
    libnuma-dev \
    # LAMMPS dependencies
    libfftw3-dev \
    libfftw3-mpi-dev \
    python3-dev \
    libibumad-dev \    
    pkg-config \
    rdma-core \
    yacc \
&& rm -rf /var/lib/apt/lists/*

# --- Install UCX ---
WORKDIR /tmp
RUN wget "https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz" && \
    tar -xzf "ucx-${UCX_VERSION}.tar.gz" && \
    cd "ucx-${UCX_VERSION}" && \
    ./configure --prefix=/opt/ucx \
        --enable-optimizations \
        --disable-logging \
        --disable-debug \
        --disable-assertions \
        --disable-params-check \
        --with-verbs \
        --with-rdmacm \
    && make -j$(nproc) && \
    make install && \
    cd /tmp && \
    rm -rf "ucx-${UCX_VERSION}" "ucx-${UCX_VERSION}.tar.gz"

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

ENV OMB_VERSION=7.5

WORKDIR /opt
ENV omb_source_tarball="osu-micro-benchmarks-${OMB_VERSION}.tar.gz"
ENV omb_url="http://mvapich.cse.ohio-state.edu/download/mvapich/${omb_source_tarball}"
RUN wget ${omb_url} --no-clobber && \
   tar -xzkf ${omb_source_tarball} 

ENV LD_LIBRARY_PATH="/usr/lib:${LD_LIBRARY_PATH}"
ENV MPICC="/usr/bin/mpicc"
ENV MPICXX="/usr/bin/mpicxx"
ENV MPIF90="/usr/bin/mpif90"

RUN cd /opt/osu-micro-benchmarks-7.5 && \
    ./configure CC=mpicc CXX=mpicxx --prefix=/usr && \
    make -j4 && make install

# Be lazy and put them on the path!
ENV OSU_PREFIX=/usr/libexec/osu-micro-benchmarks/mpi
ENV PATH=$PATH:$OSU_PREFIX/one-sided:$OSU_PREFIX/pt2pt:$OSU_PREFIX/collective:$OSU_PREFIX/congestion:$OSU_PREFIX/startup
