# Flux Usernetes on Azure

We don't have Terraform yet, so this is a "GUI" experience at the moment.

## Usage

### 1. Build Images

Since I'm new to Azure, I'm starting by creating a VM and then saving the image, which I did through the console (and saved the template) and all of the associated scripts are in [build-images](build-images). 

**CPU** 

I chose:

- ubuntu server 22.04
- South Central US
- Zone (allow auto select)
- HB120-16rs_v3 (about $4/hour)
- username: azureuser
- select your ssh key
- defaults to 30GB disk, but you should make it bigger - I skipped installing Singularity the first time because I ran out of room.

**GPU** 

 - US West 2
 - Zone (No infrastructure redundancy required)
 - ND40rs (~$22/hour)

And interactively I ran each of:

- install-deps.sh
- install-flux.sh
- install-usernetes.sh
- install-singularity.sh (skipped)
- install-lammps.sh 

And then you can actually click to create the instance group in the user interface, and it's quite easy.
You MUST call it `flux-usernetes` to derive the machine names as flux-userxxxxx OR change that prefix in the startup-script.sh. In addition, you will need to:

- Add the `startup-script.sh` to the user data section (ensure the hostname is going to be correct)
- Ensure you click on the network setup and enable the public ip address so you can ssh in
- use a pem key over a password
- Open up ports 22 for ssh, and 8050 for the flux brokers

### 2. Check Flux

Check the cluster status, the overlay status, and try running a job:

```bash
$ flux resource list
```
```bash
$ flux run -N 2 hostname
```

And lammps?

```bash
cd /home/azureuser/lammps
flux run -N 2 --ntasks 96 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 2 -v y 2 -v z 2 -in ./in.reaxff.hns -nocite
```

How to sanity check Infiniband:

```bash
ip link
# should show ib0 UP

ibv_devices 
# (should show two)
ibv_devinfo
# for a device

/etc/init.d/openibd status
```

If you need to check memory that is seen by flux:

```bash
$ flux run sh -c 'ulimit -l' --rlimit=memlock
64
```

### 3. Start Usernetes

Kubernetes autocomplete:

```bash
source <(kubectl completion bash) 
```

This is currently manual, and we need a better approach to automate it.  The first issue is the docker-compose.yaml needs
an added volume - kernel build (headers) are linked to from here:

```yaml
    volumes:
      - .:/usernetes:ro
      - /boot:/boot:ro
      - /lib/modules:/lib/modules:ro
      # This line is added
      - /usr/src:/usr/src
```

You need to first build a custom kind image base with the [Dockerfile.kind](Dockerfile.kind) to replace the Dockerfile in the "images/base" directory that you can clone from:

```bash
git clone https://github.com/kubernetes-sigs/kind
cd kind
```

Then you need to change the default base image in the kind source code:

```go
// DefaultBaseImage is the default base image used
// TODO: come up with a reasonable solution to digest pinning
// https://github.com/moby/moby/issues/43188
const DefaultBaseImage = "ghcr.io/converged-computing/kind-ubuntu:latest"
```

Build kind first:

```bash
make
```

Then clone kubernetes and use your build of kind to add the binaries to it.

```bash
git clone https://github.com/kubernetes/kubernetes
cd kubernetes
git checkout 20b216738a5e9671ddf4081ed97b5565e0b1ee01
../bin/kind build node-image
```

When that is done, tag and push to where you can control it.

```bash
docker tag kindest/node:latest ghcr.io/converged-computing/kind-ubuntu:node
docker push ghcr.io/converged-computing/kind-ubuntu:node
```

Then you need to change the FROM of the usernetes Dockerfile to use:

```dockerfile
ARG BASE_IMAGE=ghcr.io/converged-computing/kind-ubuntu:node
```
Note that I also added seccomp - I'm not sure why it was removed:

```dockerfile
RUN apt-get install -y seccomp libseccomp-dev
```

And that image build is included here with [Dockerfile.kind](Dockerfile.kind).

#### Control Plane

Let's first bring up the control plane, and we will copy the `join-command` to each node.
In the index 0 broker (the first in the broker.toml that you shelled into):

```bash
cd ~/usernetes
./start-control-plane.sh
```

Then with flux running, send to the other nodes.

```bash
flux archive create --mmap -C /home/azureuser/usernetes join-command
flux exec -x 0 -r all flux archive extract -C /home/azureuser/usernetes
```

#### Worker Nodes

**Important** your nodes need to be on the same subnet to see one another. The VPC and load balancer will require you
to create 2+, but you don't have to use them all.

```bash
cd ~/usernetes
./start-worker.sh
```

Check (from the first node) that usernetes is running:

```bash
kubectl get nodes
```

You should have a full set of usernetes node and flux alongside.

```console
ubuntu@i-059c0b325f91e5503:~$ kubectl  get nodes
NAME                  STATUS   ROLES           AGE     VERSION
u7s-flux-user000000   Ready    control-plane   2m50s   v1.30.0
u7s-flux-user000001   Ready    <none>          35s     v1.30.0
```
```console
ubuntu@i-059c0b325f91e5503:~$ flux resource list
     STATE NNODES   NCORES    NGPUS NODELIST
      free      2      192        0 flux-user[000000-000001]
 allocated      0        0        0 
      down      0        0        0 
```

At this point you can try running an experiment example.

### 4. Install Infiniband

At this point we need to expose infiniband on the host to the pods. This took a few steps,
and what I learned (and the instructions are in [the repository here](https://github.com/converged-computing/aks-infiniband-install).
