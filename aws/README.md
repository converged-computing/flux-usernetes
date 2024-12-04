# Flux Usernetes on AWS

Terraform module to create Amazon Machine Images (AMI) for Flux Framework and AWS CodeBuild.
This used to use packer, but it stopped working so now the build is a bit manual for the AMI.

## Usage

### 1. Build Images

Our builds are again working with [packer](https://developer.hashicorp.com/packer/install)! You need to install it first. You can export your AWS credentials to the environment, but I prefer to use long term credentials, as [described here](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-files.html). To build:

```bash
cd build-images
make
```

You can also look in the Makefile to see the respective commands

```bash
packer init .
packer fmt .
packer validate .
packer build flux-usernetes-build.pkr.hcl
```

The build logic is in the corresponding `build.sh` script, so if you want to add additional stuff (adding an application or other library install) write to the end of that file! Note that during the build you will see blocks of red and green. Red does *not* necessarily indicate an error. But if you do run into one that stops the build, please [open an issue](https://github.com/converged-computing/flux-usernetes/issues) to ask for help. When the build is complete it will generate what is called an AMI, an "Amazon 
Machine Image" that you can use in the next step. It should go into the `main.tf` in [tf](tf).

### 2. Deploy with Terraform

Once you have images, we deploy!

```bash
$ cd tf
```

And then init and build. Note that this will run `init, fmt, validate` and `build` in one command.
They all can be run with `make`:

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
i-0831eed34c13e747e
i-0ac10f9b787d6a349
```

Lammps should also run.

```bash
cd /home/ubuntu/lammps
flux run -N 2 --ntasks 32 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 2 -v y 2 -v z 2 -in ./in.reaxff.hns -nocite
```

You can look at the startup script logs like this if you need to debug.

```bash
cat /var/log/cloud-init-output.log
```

### 2. Usernetes

There are two ways to deploy usernetes in this system

 - Directly with the system instance (ideal for long running experiments)
 - As a batch job (ideal for emulating how it is used on an HPC cluster)

Both will be demonstrated here. Both use the wrapper to usernetes, Usernetes Python, which should be installed:

```bash
which usernetes
/usr/local/bin/usernetes
```

If you need to update, it's installed with `-e` as a development install, so you just need to pull (or otherwise update the GitHub repository there).

```bash
cd ~/usernetes-python
git pull
```

#### Usernetes System Instance

We assume you have ssh'd into the top level instance, which is where the control plane will run. You can sanity check by comparing the hostname against the first instance in `flux resource list` (they should be the same). To deploy the control plane:

```
```

This is currently manual, and we need a better approach to automate it. I think we can use `machinectl` with a uid,
but haven't tried this yet.

##### Control Plane

Let's first bring up the control plane, and we will copy the `join-command` to each node.
In the index 0 broker (the first in the broker.toml that you shelled into):

```bash
cd ~/usernetes
./start-control-plane.sh
```

Then with flux running, send to the other nodes.

```bash
# use these commands for newer flux
flux archive create --name=join-command --mmap -C /home/ubuntu/usernetes join-command
flux exec -x 0 -r all flux archive extract --name=join-command -C /home/ubuntu/usernetes
```

Note that I'm going to try a command that will be able to start the workers without needing to shell in.

```bash
cd /home/ubuntu/usernetes
flux exec -x 0 -r all --dir /home/ubuntu/usernetes /bin/bash ./start-worker.sh
```

It works! You shouldn't need to do the below.

##### Worker Nodes

**Important** This is how you'd start each manually, but you should not need to do this now with the final command about to run the same script across workers from the control plane. This is what I did before I figured that out. Also note that your nodes need to be on the same subnet to see one another. The VPC and load balancer will require you to create 2+, but you don't have to use them all. That information is embedded in the terraform config now.

```bash
cd ~/usernetes

# start the worker (to hopefully join)
./start-worker.sh
```

Check (from the first node) that usernetes is running (your KUBECONFIG should be exported):

```bash
. ~/.bashrc
kubectl get nodes
```

You should have a full set of usernetes node and flux alongside.

```console
$ kubectl get nodes
NAME                      STATUS   ROLES           AGE   VERSION
u7s-i-0a7c8e4a2ddaffbe9   Ready    <none>          33s   v1.29.1
u7s-i-0be1a2884b2873c22   Ready    control-plane   11m   v1.29.1
```
```console
$ flux resource list
     STATE NNODES   NCORES    NGPUS NODELIST
      free      2       32        0 i-0be1a2884b2873c22,i-0a7c8e4a2ddaffbe9
 allocated      0        0        0 
      down      0        0        0 
```

### Topology

We can get our topology for later:

```bash
aws ec2 describe-instance-topology --region us-east-1 --filters Name=instance-type,Values=hpc7g.4xlarge > topology-32.json
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
