compute_family = "usernetes-gpu-ubuntu"
compute_node_specs = [
  {
    name_prefix  = "flux"
    machine_arch = "x86-64"
    machine_type = "n1-standard-8"
    gpu_type     = "nvidia-tesla-v100"
    gpu_count    = 1
    compact      = false
    instances    = 2
    properties   = []
    boot_script  = <<BOOT_SCRIPT
#!/bin/sh

sudo modprobe ip6_tables
sudo modprobe ip6table_nat
sudo modprobe iptable_nat

sudo rm -rf /etc/cdi/nvidia.yaml
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --device-name-strategy=uuid
systemctl --user restart docker.service

mkdir -p /var/nfs/home || true
chown nobody:nobody /var/nfs/home || true

# This enables NFS
nfsmounts=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/nfs-mounts" -H "Metadata-Flavor: Google")

if [[ "X$nfsmounts" != "X" ]]; then
    echo "Enabling NFS mounts"
    share=$(echo $nfsmounts | jq -r '.share')
    mountpoint=$(echo $nfsmounts | jq -r '.mountpoint')

    bash -c "sudo echo $share $mountpoint nfs defaults,hard,intr,_netdev 0 0 >> /etc/fstab"
    mount -a
fi
BOOT_SCRIPT

  },
]
compute_scopes = ["cloud-platform"]
