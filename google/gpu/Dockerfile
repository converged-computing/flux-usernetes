ARG BASE_IMAGE=docker.io/kindest/node:v1.32.1@sha256:6afef2b7f69d627ea7bf27ee6696b6868d18e03bf98167c420df486da4662db6
ARG CNI_PLUGINS_VERSION=v1.6.2
ARG HELM_VERSION=v3.17.0
ARG FLANNEL_VERSION=v0.26.4
FROM ${BASE_IMAGE}
COPY Dockerfile.d/SHA256SUMS.d/ /tmp/SHA256SUMS.d
ARG CNI_PLUGINS_VERSION
ARG HELM_VERSION
ARG FLANNEL_VERSION
RUN arch="$(uname -m | sed -e s/x86_64/amd64/ -e s/aarch64/arm64/)" && \
  fname="cni-plugins-linux-${arch}-${CNI_PLUGINS_VERSION}.tgz" && \
  curl -o "${fname}" -fSL "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/${fname}" && \
  grep "${fname}" "/tmp/SHA256SUMS.d/cni-plugins-${CNI_PLUGINS_VERSION}" | sha256sum -c && \
  mkdir -p /opt/cni/bin && \
  tar xzf "${fname}" -C /opt/cni/bin && \
  rm -f "${fname}" && \
  fname="helm-${HELM_VERSION}-linux-${arch}.tar.gz" && \
  curl -o "${fname}" -fSL "https://get.helm.sh/${fname}" && \
  grep "${fname}" "/tmp/SHA256SUMS.d/helm-${HELM_VERSION}" | sha256sum -c && \
  tar xzf "${fname}" -C /usr/local/bin --strip-components=1 -- "linux-${arch}/helm" && \
  rm -f "${fname}" && \
  fname="flannel.tgz" && \
  curl -o "${fname}" -fSL "https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/${fname}" && \
  grep "${fname}" "/tmp/SHA256SUMS.d/flannel-${FLANNEL_VERSION}" | sha256sum -c && \
  tar xzf "${fname}" -C / && \
  rm -f "${fname}"
# gettext-base: for `envsubst`
# moreutils: for `sponge`
# socat: for `socat` (to silence "[WARNING FileExisting-socat]" from kubeadm)
RUN apt-get update && apt-get install -y --no-install-recommends \
  gettext-base \
  moreutils \
  socat
ADD Dockerfile.d/etc_udev_rules.d_90-flannel.rules /etc/udev/rules.d/90-flannel.rules
ADD Dockerfile.d/u7s-entrypoint.sh /
RUN apt-get install -y gnupg2 && apt-get update

# If not set, is set to "void"
ENV NVIDIA_VISIBLE_DEVICES=all

RUN /bin/bash -c "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list" && apt-get update && apt-get install -y nvidia-container-toolkit && nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid

# In practice I didn't need this either.
# This is run in entrypoint
# nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid && nvidia-ctk cdi list && nvidia-ctk config --in-place --set nvidia-container-runtime.mode=cdi && nvidia-ctk runtime configure --runtime=containerd --cdi.enabled && systemctl restart containerd

ENTRYPOINT ["/u7s-entrypoint.sh", "/usr/local/bin/entrypoint", "/sbin/init"]

