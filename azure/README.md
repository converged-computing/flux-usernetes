# Flux Usernetes on Azure

We don't have Terraform yet, so this is a "GUI" experience at the moment.

## Usage

### 1. Build Images

Since I'm new to Azure, I'm starting by creating a VM and then saving the image, which I did through the console (and saved the template) and all of the associated scripts are in [build-images](build-images). I chose:

- ubuntu server 22.04
- South Central US
- Zone (allow auto select)
- HB120-16rs_v3 (about $4/hour)
- username: azureuser
- select your ssh key
- defaults to 30GB disk, but you should make it bigger - I skipped installing Singularity the first time because I ran out of room.

And interactively I ran each of:

- install-deps.sh
- install-flux.sh
- install-usernetes.sh
- install-singularity.sh (skipped)
- install-lammps.sh 

And then you can actually click to create the instance group in the user interface, and it's quite easy.
You MUST call it `flux-usernetes` to derive the machine names as flux-userxxxxx OR change that prefix in the startup-script.sh
In addition, you will need to:

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

If you need to check memory that is seen by flux:

```bash
$ flux run sh -c 'ulimit -l' --rlimit=memlock
64
```

### 3. Start Usernetes

This is currently manual, and we need a better approach to automate it. I think we can use `machinectl` with a uid,
but haven't tried this yet.

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

At this point we need to expose infiniband on the host to the pods. This took a few steps.

1. A custom build of the driver install image, which I have on the [branch here](https://github.com/researchapps/aks-rdma-infiniband/tree/update-ubuntu-22.04). The changes are updating the base image (ubuntu 22.04) to match the Ubuntu HPC/AI image on Azure, and then retrieving the updated Mellanox drivers (an .iso that you have to download and copy in).
2. Pushing the image to our registry [ghcr.io/converged-computing/rdma-infiniband:ubuntu-22.04](https://github.com/converged-computing/performance-study/pkgs/container/rdma-infiniband)
3. Updating configs in [infiniband/install](infiniband/install) to reflect these changes.

Then you'll need to clone this repository onto your Microsoft VMs to get these configs, and:

```bash
git clone -b add-azure https://github.com/converged-computing/flux-usernetes /home/azureuser/flux-usernetes
cd /home/azureuser/flux-usernetes/azure/infiniband
kubectl apply -k ./infiniband/install
```
