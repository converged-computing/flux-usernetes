# Flux Usernetes on AWS

Terraform module to create Amazon Machine Images (AMI) for Flux Framework and AWS CodeBuild.
This used to use packer, but it stopped working so now the build is a bit manual for the AMI.

## Usage

### 1. Build Images

Note that we previously built with packer. That no longer seems to work ([maybe this issue](https://github.com/hashicorp/packer/issues/8180))
Instead we are going to run the commands there manually and save the AMI. The previous instruction was to export AWS credentials, cd into build-images,
and `make`. For the manual build, you'll need to create an m5.large instance in the web UI, ubuntu 22.04, and manually run the contents of each
of the scripts in [build-images](build-images). For example, for the top AMI below I ran each of:

- install-deps.sh
- install-flux.sh
- install-usernetes.sh
- install-singularity.sh
- install-lammps.sh 

The scripts have been modified for ARM, since AMD64 doesn't really work with the limited network options (we need the HPC instances). And this generated the following (not all of these may exist anymore, we did a cleanup):

- flux-ubuntu-usernetes-efa `ami-03bf34a7d8b789694` openmpi and efa provided by the efa install, and version 1.30.0
- flux-ubuntu-usernetes-lammps-openmpi-singularity `ami-070478bc8c3200e41` using openmpi instead of mpich
- flux-usernetes-lammps-singularity-libfabricc: `ami-099e87e49f153b2b3` the same, but building MPI with system (not AWS)
- flux-ubuntu-usernetes-lammps-singularity-arm-efa: `ami-088dc4371888c26cb` the same but with those things!
- flux-ubuntu-usernetes: `ami-023a3bf52034d3faa` has flux, usernetes, lammps, and singularity

Nothing really works on AWS without EFA so probably we will use the first (top).

### Deploy with Terraform

Once you have images, we deploy!

```bash
$ cd tf
```

And then init and build:

```bash
$ make init
$ make fmt
$ make validate
$ make build
```

And they all can be run with `make`:

```bash
$ make
```

You can then shell into any node, and check the status of Flux. I usually grab the instance
name via "Connect" in the portal, but you could likely use the AWS client for this too.

```bash
$ ssh -o 'IdentitiesOnly yes' -i "mykey.pem" ubuntu@ec2-xx-xxx-xx-xxx.compute-1.amazonaws.com
```

#### Check Flux

Check the cluster status, the overlay status, and try running a job:

```bash
$ flux resource list
     STATE NNODES   NCORES NODELIST
      free      2        2 i-012fe4a110e14da1b,i-0354d878a3fd6b017
 allocated      0        0 
      down      0        0 
```
```bash
$ flux run -N 2 hostname
i-012fe4a110e14da1b.ec2.internal
i-0354d878a3fd6b017.ec2.internal
```

You can look at the startup script logs like this if you need to debug.

```bash
$ cat /var/log/cloud-init-output.log
```

#### Start Usernetes

This is currently manual, and we need a better approach to automate it. I think we can use `machinectl` with a uid,
but haven't tried this yet.

##### Control Plane

Let's first bring up the control plane, and we will copy the `join-command` to each node.
In the index 0 broker (the first in the broker.toml that you shelled into):

```bash
cd ~/usernetes

# This needs to be run by the user again in the shell
/usr/bin/dockerd-rootless-setuptool.sh uninstall -f 
/usr/bin/rootlesskit rm -rf /home/ubuntu/.local/share/docker
sudo chown -R $USER /home/ubuntu
dockerd-rootless-setuptool.sh install
docker run hello-world

# start the control plane
./start-control-plane.sh
```

Then with flux running, send to the other nodes.

```bash
flux filemap map -C /home/ubuntu/usernetes join-command
flux exec -x 0 -r all flux filemap get -C /home/ubuntu/usernetes
```

##### Worker Nodes

**Important** your nodes need to be on the same subnet to see one another. The VPC and load balancer will require you
to create 2+, but you don't have to use them all.

```bash
cd ~/usernetes

# This needs to be run by the user again in the shell
/usr/bin/dockerd-rootless-setuptool.sh uninstall -f 
/usr/bin/rootlesskit rm -rf /home/ubuntu/.local/share/docker
sudo chown -R $USER /home/ubuntu
dockerd-rootless-setuptool.sh install
docker run hello-world

# start the worker (to hopefully join)
./start-worker.sh
```

Check (from the first node) that usernetes is running:

```bash
kubectl get nodes
```

You should have a full set of usernetes node and flux alongside.

```console
ubuntu@i-059c0b325f91e5503:~$ kubectl  get nodes
NAME                      STATUS   ROLES           AGE     VERSION
u7s-i-011e558c998efa7c9   Ready    <none>          67s     v1.29.1
u7s-i-049a938f182420a7b   Ready    <none>          36s     v1.29.1
u7s-i-059c0b325f91e5503   Ready    control-plane   7m35s   v1.29.1
u7s-i-0a5b50dbcf4754bb1   Ready    <none>          3m8s    v1.29.1
u7s-i-0cb613bda0f908a84   Ready    <none>          5m17s   v1.29.1
u7s-i-0cdc86ed08f06dd11   Ready    <none>          2m34s   v1.29.1
u7s-i-0d58764791da6b74e   Ready    <none>          4m25s   v1.29.1
```
```console
ubuntu@i-059c0b325f91e5503:~$ flux resource list
     STATE NNODES   NCORES    NGPUS NODELIST
      free      7       56        0 i-059c0b325f91e5503,i-0cb613bda0f908a84,i-0d58764791da6b74e,i-0a5b50dbcf4754bb1,i-0cdc86ed08f06dd11,i-011e558c998efa7c9,i-049a938f182420a7b
 allocated      0        0        0 
      down      0        0        0 
```

At this point you can try running an experiment example.

## Debugging

Here are some debugging tips for network. Ultimately the fix was requesting one subnet
to be used by the autoscaling group (and I didn't need these) but I want to preserve
them from our conversation.

- Look at routing between subnets (e.g., create two instances and try curl/ping)
- Look at launch template configs for launch template - figure out if something looks wrong and trace back to terraform
- Try the [Reachability analyzer](https://console.aws.amazon.com/networkinsights/home#ReachabilityAnalyzer)
  - Create an analyze path, sources and destinations 
- eips - elastic ips? (default is 5, but can request quota higher)
- have the node groups across AZs but have it launch everything in one AZ by specifying the subset we want for the actual instances to launch in (this was it!)
