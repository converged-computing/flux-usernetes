# Usernetes with GPU

I didn't install flux because the gcc was too old.

## Usage

Bring up the cluster.

```bash
cd ./tf
make
cd ../
```

Then you'll need to add an ephemeral IP address to flux-001, and ssh into it as jupyter. This should work given you have built the machine with an ssh authorized key added.

```bash
ssh -o IdentitiesOnly=yes jupyter@23.251.159.199
```

### Control Plane


Determine that nvidia is a runtime option, and rootless is supported:

```console
docker info | grep -i runtimes
 Runtimes: io.containerd.runc.v2 nvidia runc

docker info | grep root
  rootless
```

```bash
cd /opt/usernetes
make up
sleep 5
make kubeadm-init
make install-flannel
make kubeconfig
export KUBECONFIG=/opt/usernetes/kubeconfig
kubectl get pods
make join-command
```

Create a hosts file to use with pssh

```bash
for number in $(seq 2 9)
  do
    echo $number
done
```

Copy key to worker nodes (TODO, parallel ssh install) and key already on nodes.

```bash
scp ./join-command flux-002:/opt/usernetes/join-command
ssh flux-002 make -C /opt/usernetes up 
sleep 5
ssh flux-002 make -C /opt/usernetes kubeadm-join
```

Then finish on the control plane:

```bash
make sync-external-ip
```

If you need to test the nvidia runtime:

```console
docker run --rm -ti --device=nvidia.com/gpu=all ubuntu nvidia-smi -L
GPU 0: Tesla V100-SXM2-16GB (UUID: GPU-798e9725-623d-ca7f-f15d-b1908ec8bb0d)
GPU 1: Tesla V100-SXM2-16GB (UUID: GPU-be5719da-cd52-8a40-09bb-0007224e9236)
```

Prepare the control plane:

```bash
kubectl taint nodes u7s-$(hostname) node-role.kubernetes.io/control-plane:NoSchedule-
source <(kubectl completion bash)
kubectl get nodes
```

And deploy the driver installers:

```bash
kubectl apply -f nvidia-device-plugin.yml
```

See the nvidia device plugin pods, and check that GPU are found:

```bash
kubectl  get pods -n kube-system
kubectl  logs -n kube-system nvidia-device-plugin-daemonset-2vxcv 
```

<details>

<summary>Finding GPU Device</summary>

```
I0222 08:03:46.210342       1 main.go:235] "Starting NVIDIA Device Plugin" version=<
	d475b2cf
	commit: d475b2cfcf12b983a4975d4fc59d91af432cf28e
 >
I0222 08:03:46.213554       1 main.go:238] Starting FS watcher for /var/lib/kubelet/device-plugins
I0222 08:03:46.213756       1 main.go:245] Starting OS watcher.
I0222 08:03:46.214103       1 main.go:260] Starting Plugins.
I0222 08:03:46.214154       1 main.go:317] Loading configuration.
I0222 08:03:46.215464       1 main.go:342] Updating config with default resource matching patterns.
I0222 08:03:46.215695       1 main.go:353] 
Running with config:
{
  "version": "v1",
  "flags": {
    "migStrategy": "none",
    "failOnInitError": false,
    "mpsRoot": "",
    "nvidiaDriverRoot": "/",
    "nvidiaDevRoot": "/",
    "gdsEnabled": false,
    "mofedEnabled": false,
    "useNodeFeatureAPI": null,
    "deviceDiscoveryStrategy": "tegra",
    "plugin": {
      "passDeviceSpecs": false,
      "deviceListStrategy": [
        "envvar"
      ],
      "deviceIDStrategy": "uuid",
      "cdiAnnotationPrefix": "cdi.k8s.io/",
      "nvidiaCTKPath": "/usr/bin/nvidia-ctk",
      "containerDriverRoot": "/driver-root"
    }
  },
  "resources": {
    "gpus": [
      {
        "pattern": "*",
        "name": "nvidia.com/gpu"
      }
    ]
  },
  "sharing": {
    "timeSlicing": {}
  },
  "imex": {}
}
I0222 08:03:46.215713       1 main.go:356] Retrieving plugins.
I0222 08:03:46.216188       1 server.go:195] Starting GRPC server for 'nvidia.com/gpu'
I0222 08:03:46.217364       1 server.go:139] Starting to serve 'nvidia.com/gpu' on /var/lib/kubelet/device-plugins/nvidia-gpu.sock
I0222 08:03:46.220361       1 server.go:146] Registered device plugin for 'nvidia.com/gpu' with Kubelet
```
</details>

Then install the GPU operator

```bash
kubectl create ns gpu-operator
source <(kubectl completion bash)
kubectl get nodes
```

Install the GPU operator.

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
helm install gpu-operator --wait -n gpu-operator --create-namespace nvidia/gpu-operator --version=v24.9.2
```

The docker daemon.json should look like this:

```json
{
    "features": {
        "cdi": true
    },
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    }
}
```

Wait for GPU to show up:

```bash
kubectl  get nodes -o json | jq -r .items[].status.capacity
```
```console
{
  "cpu": "8",
  "ephemeral-storage": "263967572Ki",
  "hugepages-1Gi": "0",
  "hugepages-2Mi": "0",
  "memory": "30817504Ki",
  "nvidia.com/gpu": "1",
  "pods": "110"
}
{
  "cpu": "8",
  "ephemeral-storage": "263967572Ki",
  "hugepages-1Gi": "0",
  "hugepages-2Mi": "0",
  "memory": "30817504Ki",
  "nvidia.com/gpu": "1",
  "pods": "110"
}
```

Install the pytorch operator.

```bash
kubectl apply --server-side -k "github.com/kubeflow/training-operator.git/manifests/overlays/standalone?ref=v1.8.1"
```
```bash
kubectl apply -f simple.yaml
```

## Experiment

### GPU

#### 1 node, 2 GPU/worker, n1-standard-16

This was run with rootful docker. The extended setup never worked (reproduced).

- 1 node, 2 GPU/node, batch 128, 20 epochs: 2m29.363s
- 1 node, 2 GPU/node, batch 128, 10 epochs: 1m13.362s
- 1 node, 2 GPU/node, batch 128, 8 epochs: 1m4.855s
- 1 node, 2 GPU/node, batch 128, 4 epochs: 50.270s
- 1 node, 2 GPU/node, batch 128, 2 epochs: 0m25.609s
- 1 node, 2 GPU/node, batch 128, 1 epochs: 0m20.057s


