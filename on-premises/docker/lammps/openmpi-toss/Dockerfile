FROM ghcr.io/converged-computing/lc-toss4-base:toss.4.8-2.x86_64

COPY ./rpms /rpms

RUN dnf install -y perl rpmrebuild vim tcl-devel wget && \
    dnf install -y python39 python39-cffi python39-ply python39-yaml && \
    rpm -i ./rpms/pkgconf-pkg-config-1.4.2-1.el8.x86_64.rpm && \
    rpm -i ./rpms/mlnx-ofa_kernel-modules-25.01-0.6.0.1.0.5mofed.t4.x86_64.rpm && \
    rpm -i ./rpms/pmix-3.2.5-0.2mofed.t4.x86_64.rpm && \
    rpm -i ./rpms/kernel-headers-4.18.0-553.53.1.1toss.t4.x86_64.rpm && \
    rpm -i ./rpms/libnl3-* && \
    rpm -i ./rpms/libibverbs-* && \
    rpm -i ./rpms/logrotate-3.14.0-6.el8.x86_64.rpm 
    rpm -i ./rpms/munge-*
    rpm -i ./rpms/libibumad-2501mlnx56-1.2501060.x86_64.rpm && \
    rpm -i ./rpms/librdmacm-* && \
    rpm -i ./rpms/jansson-* && \
    rpm -i ./rpms/infiniband-diags-2501mlnx56-1.2501060.x86_64.rpm && \
    rpm -i ./rpms/zlib-devel-1.2.11-25.el8.x86_64.rpm && \
    rpm -i ./rpms/hwdata-0.314-8.8.el8.noarch.rpm && \
    rpm -i ./rpms/pciutils* && \
    rpm -i ./rpms/rdma-core-* && \
    rpm -i ./rpms/python3-* && \
    rpm -i ./rpms/libsodium-* && \
    rpm -i ./rpms/flux-security-0.14.0-1.t4.x86_64.rpm && \
    dnf install -y cairo-devel && \
    rpm -i ./rpms/flux-core-0.74.0-2.t4.x86_64.rpm && \
    rpm -i rpms/ibutils2-2.1.1-0.22100.MLNX20250123.g26a775d8.2501060.x86_64.rpm  && \
    rpm -i ./rpms/mlnx-tools-25.01-0.2501060.x86_64.rpm && \
    rpm -i ./rpms/lsof-4.93.2-1.el8.x86_64.rpm && \
    rpm -i ./rpms/ocl-icd-* && \
    rpm -i ./rpms/hwloc-* && \
    rpm -i ./rpms/lua-* && \
    rpm -i ./rpms/flux-core-0.74.0-2.t4.x86_64.rpm && \
    # rpmrebuild --edit-spec --package ./rpms/mlnx-ofa_kernel-25.04-0.6.0.1.0.2mofed.t4.x86_64.rpm
    # Comment out requires line for kernel version - isn't exact match. Save and copy as edited
    rpm -i ./rpms/mlnx-ofa_kernel-25.04-0.6.0.1.0.2mofed.t4.x86_64_edited.rpm && \
    rpm -i ./rpms/mlnx-ofa_kernel-devel* && \
    rpm -i ./rpms/mlnx-ofa_kernel-modules*
    rpm -i ./rpms/mlnx-ofa_kernel-devel* && \
    rpm -i ./rpms/mlnx-ofa_kernel-modules* && \
    rpm -i ./rpms/mlnx-ofa* && \
    # Note skipping cuda for now
    rpm -i rpms/ucx-1.18.0-12501060.1mofed.t4.x86_64.rpm && \
    rpm -i rpms/ucx-cma-1.18.0-12501060.1mofed.t4.x86_64.rpm && \
    # rpms/ucx-cuda-1.18.0-12501060.1mofed.t4.x86_64.rpm && \
    rpm -i rpms/ucx-devel-1.18.0-12501060.1mofed.t4.x86_64.rpm && \
    # rpms/ucx-gdrcopy-1.18.0-12501060.1mofed.t4.x86_64.rpm && \
    rpm -i rpms/ucx-ib-1.18.0-12501060.1mofed.t4.x86_64.rpm && \
    rpm -i rpms/ucx-rdmacm-1.18.0-12501060.1mofed.t4.x86_64.rpm && \
    rpm -i rpms/numactl-*  && \
    rpm -i rpms/lua-lpeg-1.0.1-6.el8.x86_64.rpm && \
    rpm -i rpm -i rpms/lua-* && \
    dnf install -y lua-filesystem lua-json lua-term && \
    rpm -i rpms/Lmod-8.7.7-1.1toss.t4.x86_64.rpm && \    
    dnf install -y java-openjdk-headless && \
    dnf install -y gcc-gfortran gcc-c++ && \
    rpm -i rpms/opensm-* && \
    rpm -i rpms/libpsm2-* && \
    rpm -i rpms/openmpi-4.1-gnu-4.1.6-3.1mofed.t4.x86_64.rpm && \
    rpm -i /rpms/fftw-*

