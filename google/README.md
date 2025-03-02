# Usernetes and Flux on "Bare Metal" on Google Cloud Compute Engine

This is a setup akin to Cluster Toolkit (using Terraform) to run Flux on Google Cloud, and add Usernetes.
Google Cloud does not support any kind of special networking, so we will rely on ethernet. This setup comes also with Singularity and a "bare metal" install of lammps. You'll need to build from [build-images](build-images).

## Included:

 - [gpu](gpu): A GPU setup that also installs the nvidia device plugin, exposed with CDI and the nvidia container runtime.
 - [experiment](https://github.com/converged-computing/google-performance-study/tree/main/experiments/usernetes/mnist-gpu): Small experiments with Usernetes and GPU (in another repository)

## Usage

### Create Google Service Accounts

Create default application credentials (just once):

```bash
$ gcloud auth application-default login
```

You can build the base VM with [build-images](build-images). Then cd to terraform, edit the basic.tfvars with
variables at the top, and in the startup script **IMPORTANT** you need to login as ubuntu, so you need to add a public key where it's asked for. The configuration
of flux is currently hard coded to support up to 999 instances - I used to customize it, but we can create a subinstance
with `flux alloc -N <size>` and it seems unlikely we'd ever get more than that on cloud. But if we needed that, it simply
means writing the file over. Then:

```bash
make
```

Note that you need to go to flux-001 -> Edit -> Network interfaces and give it an ephemeral Ip address. Then you can ssh in as user ubuntu, which has
everything setup already. Instead of the gcloud command, you'll want to do something like:

```bash
ssh ubuntu@<address>
```

And that will work if your key is added.

### Control Plane

Start an instance so you have owner privileges.

```bash
cd /opt/software/usernetes
flux alloc -N 2
```

Let's first bring up the control plane, and we will copy the `join-command` to each node.
In the index 0 broker (the first in the broker.toml that you shelled into):

```bash
cd /opt/software/usernetes
./start-control-plane.sh
```

Then with flux running, send to the other nodes.

```bash
# use these commands for newer flux
flux archive create --name=join-command --mmap -C /opt/software/usernetes join-command
flux exec -x 0 -r all flux archive extract --name=join-command -C /opt/software/usernetes
```

Then start workers on other nodes.

```bash
flux exec -x 0 -r all --dir /opt/software/usernetes /bin/bash ./start-worker.sh
```

It works! You should not need to do manual setup on the workers, phew.
When that is done, run this final step on your host (control plane):

```bash
make sync-external-ip
```

Check (from the first node) that usernetes is running (your KUBECONFIG should be exported):

```bash
. ~/.bashrc
kubectl get nodes
```

You should have a full set of usernetes node and flux alongside.

```console
$ kubectl get nodes
NAME           STATUS   ROLES           AGE   VERSION
u7s-flux-001   Ready    control-plane   99s   v1.31.0
u7s-flux-002   Ready    <none>          10s   v1.31.0
```
```console
$ flux resource list
     STATE NNODES   NCORES    NGPUS NODELIST
      free      2      112        0 flux-[001-002]
 allocated      0        0        0 
      down      0        0        0 
```

## Experiment

Let's test running lammps:

- on bare metal
- with singularity
- in usernetes

## Bare Metal

```bash
cd /opt/software/lammps/examples/reaxff/HNS
```
```bash
# 53 seconds
flux run --env OMPI_MCA_btl_tcp_if_include=ens4 -N 2 --ntasks 112 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite

# 30 seconds
flux run --env OMPI_MCA_btl_tcp_if_include=ens4 -N 2 --ntasks 112 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 8 -v z 8 -in ./in.reaxff.hns -nocite

# 18 seconds
flux run --env OMPI_MCA_btl_tcp_if_include=ens4 -N 2 --ntasks 112 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 8 -v y 8 -v z 8 -in ./in.reaxff.hns -nocite
```

Now container runs for lammps. This container needs a pull to all nodes.

```bash
cd /opt/software
flux exec --rank all --dir /opt/software singularity pull docker://ghcr.io/converged-computing/metric-lammps-cpu:zen4-reax
container=/opt/software/metric-lammps-cpu_zen4-reax.sif 
```

And the same, using a container:

```console
cd /opt/software/lammps/examples/reaxff/HNS

# 53 seconds
flux run --env OMPI_MCA_btl_tcp_if_include=ens4 -N 2 --ntasks 112 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns

# 29 seconds
flux run --env OMPI_MCA_btl_tcp_if_include=ens4 -N 2 --ntasks 112 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 8 -v z 8 -in ./in.reaxff.hns

# 18 seconds
flux run --env OMPI_MCA_btl_tcp_if_include=ens4 -N 2 --ntasks 112 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 8 -v z 8 -in ./in.reaxff.hns
```

Now User space Kubernetes

```bash
# Autocomplete
source <(kubectl completion bash) 
```

Install the Flux Operator.

```bash
kubectl apply -f https://raw.githubusercontent.com/flux-framework/flux-operator/main/examples/dist/flux-operator.yaml
```

```console
cp flux-usernetes/aws/examples/lammps/crd/minicluster-efa.yaml .
# vim minicluster-efa.yaml
```

Prepare to run.

```bash
# Create output directory for results
mkdir -p ./results/usernetes
```

Write this minicluster.yaml to file:

```yaml
apiVersion: flux-framework.org/v1alpha2
kind: MiniCluster
metadata:
  name: flux-sample
spec:
  size: 2
  tasks: 112
  flux:
    container:
      disable: true

  containers:
  - image: ghcr.io/converged-computing/metric-lammps-cpu:zen4-reax
    workingDir: /code
    command: lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite
```

And:

```bash
kubectl apply -f minicluster.yaml
kubectl logs flux-sample-0-xxxx -f
```

I did this for three problem sizes to get the wall times. For each, to add shared memory:

```yaml
    volumes:
      # Ensure /dev/shm does not limit efa
      shared-memory:
        emptyDir: true
        emptyDirMedium: "memory"
```

- 16 x 16 x 8 (no shmem volume): 1m 15s
- 16 x 16 x 8 (shmem volume): 1m 18s

Wow, quite a bit slower. We don't have the bypass here.
