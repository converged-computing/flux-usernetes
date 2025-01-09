# Flux Usernetes on Azure

## Usage

### 1. Build Images

You'll need to do the [build](build), first, and before that creating a resource group with your packer image (e.g., packer-testing) and an image (e.g., flux-usernetes) before continuing here. 

### 2. Deploy Terraform

The repository has these instructions in more detail, and we can repeat them here:
Export your image build identifier to the environment:

```bash
export TF_VAR_vm_image_storage_reference="/subscriptions/3e173a37-8f81-492f-a234-ca727b72e6f8/resourceGroups/packer-testing/providers/Microsoft.Compute/images/flux-usernetes"
```

Note that I needed to clone this and do from the cloud shell in the Azure portal.

```bash
git clone https://github.com/converged-computing/flux-usernetes
cd flux-usernetes/azure
```

After tweaking the main.tf and startup-script.sh scripts to your liking:

```bash
make apply-approved
```

It only takes a little over a minute! When it's done, save the public and private key to local files:

```bash
terraform output -json public_key | jq -r > id_azure.pub
terraform output -json private_key | jq -r > id_azure
chmod 600 id_azure*
```

### 3. Check Cluster

#### Check Lead Broker

Azure VM Scale sets unfortunately don't give you reliable instance ids. So we need to check if we got a lead broker with all zeros. Run this:

```bash
lead_broker=$(az vmss list-instances -g terraform-testing -n flux | jq -r .[0].osProfile.computerName)
echo "The lead broker is ${lead_broker}"
```
If you get this, you are good!

```bash
The lead broker is flux000000
```

Any other number you need to update the brokers, and the repository has a script for that. To run in parallel, let's write a list of hosts, and then issue the command. You'll want to write this hosts file for running any command (bash script) in parallel across nodes with ssh.

```bash
for address in $(az vmss list-instance-public-ips -g terraform-testing -n flux | jq -r .[].ipAddress)
  do
    echo "azureuser@$address" >> hosts.txt
done
```

Install parallel ssh:

```bash
git clone https://github.com/lilydjwg/pssh /tmp/pssh
export PATH=/tmp/pssh/bin:$PATH
```

#### Fixing Lead Broker

> Only required if the lead broker is not `flux000000`

And here is how you can fix all your brokers (if you need to, if you have all zeros you are good).
Note that you need to accept the ssh - we might need to add `ssh -o StrictHostKeyChecking=no` or the same to `/etc/ssh/ssh_config` (I can't do this from the cloud shell):

```bash
for address in $(az vmss list-instance-public-ips -g terraform-testing -n flux | jq -r .[].ipAddress)
 do
   echo "Updating $address"
   scp -i ./id_azure update_brokers.sh azureuser@${address}:/tmp/update_brokers.sh
   # This is what the command would look like in serial
   # ssh -i ./id_azure azureuser@$address "/bin/bash /tmp/update_brokers.sh flux $lead_broker"
done

# This is done in parallel
pssh -h hosts.txt -x "-i ./id_azure" "/bin/bash /tmp/update_brokers.sh flux $lead_broker"
```

Note that if it fails, you need to wait a bit - I usually step away for a second or two to give the VM time to finish setting up.

#### Check Storage

I've seen the same deployment recipe bring up nodes that don't have storage updated. We need to check if we expect installs and container pulls to work.

```bash
for address in $(az vmss list-instance-public-ips -g terraform-testing -n flux | jq -r .[].ipAddress)
 do
   ssh -i ./id_azure azureuser@$address "df -h" | grep /dev/root
done
```

### 4. Install LAMMPS and OSU

Before we shell in, let's install lammps and the osu benchmarks on "bare metal":

```console
for script in $(echo lammps osu)
  do
  for address in $(az vmss list-instance-public-ips -g terraform-testing -n flux | jq -r .[].ipAddress)
    do
     echo "Installing ${script} to $address"
     scp -i ./id_azure ./install/install_${script}.sh azureuser@${address}:/tmp/install_${script}.sh
     # This is the serial command if you need to test
     # ssh -i ./id_azure azureuser@${address} /bin/bash /tmp/install_${script}.sh
    done
    pssh -h hosts.txt -x "-i ./id_azure" "/bin/bash /tmp/install_${script}.sh"
done
```

This installs to `/usr/local/libexec/osu-micro-benchmarks/mpi`. And lammps installs to `/usr/bin/lmp`

### 5. SSH in and Check Flux

Then get the instance ip addresses from the command line (or portal), and ssh in!

```bash
ip_address=$(az vmss list-instance-public-ips -g terraform-testing -n flux | jq -r .[0].ipAddress)
ssh -i ./id_azure azureuser@${ip_address}
```

To get a difference instance, just change the index (e.g., index 1 is the second instance)
Check the cluster status and try running a job. Give it at least a minute to finish the cloud init script, bootstrap, etc.

```bash
flux resource list
```
```bash
flux run -N 2 hostname
```

Note that a huge number of brokers will be listed as offline. We do this because Flux can see nodes that don't exist as offline, and if we increase the size of the cluster they can join easily. 

### 6. Check Infiniband

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
flux run sh -c 'ulimit -l' --rlimit=memlock
unlimited
```

### 7. OSU Benchmarks

Singularity is installed in the VM. Let's use flux exec to issue a command to the other broker and pull singularity containers. These two containers have the same stuff as the host! This is why you typically want to create nodes with a large disk - these containers are chonky.

```bash
flux exec --rank 0-1 singularity pull docker://ghcr.io/converged-computing/flux-tutorials:azurehpc-2204-osu
```

Let's run each with Flux. Note that you likely need to adjust the `UCX_TLS` parameter.

```bash
# OSU all reduce
binds=/opt/hpcx-v2.15-gcc-MLNX_OFED_LINUX-5-ubuntu22.04-cuda12-gdrcopy2-nccl2.17-x86_64/:/opt/hpcx-v2.19-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64
flux run -N2 -n 192 -o cpu-affinity=per-task singularity exec --bind ${binds} --env UCX_TLS=ib --env UCX_NET_DEVICES=mlx5_ib0:1 ./flux-tutorials_azurehpc-2204-osu.sif /bin/bash -c ". /source-hpcx.sh && hpcx_load && /opt/osu-benchmark/build.openmpi/mpi/collective/osu_allreduce"
```

Test against the bare metal.

```bash
flux run -N2 -n 192 -o cpu-affinity=per-task --env UCX_TLS=ib --env UCX_NET_DEVICES=mlx5_ib0:1 /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce
```

Spoiler - with the binds to the host, the Singularity container is faster.

<details>

<summary>OSU All Reduce on Bare Metal vs. Singularity</summary>

```console
# Singularity container

# OSU MPI Allreduce Latency Test v5.8
# Size       Avg Latency(us)
4                       4.74
8                       4.63
16                      4.68
32                      5.03
64                      5.13
128                     5.27
256                     6.41
512                     5.78
1024                    6.31
2048                    7.86
4096                   11.02
8192                   15.53
16384                  25.67
32768                 277.20
65536                 772.32
131072               1453.79
262144               3777.81
524288               7159.46
1048576             10860.68

# Bare metal VM

# OSU MPI Allreduce Latency Test v5.8
# Size       Avg Latency(us)
4                       5.26
8                       5.14
16                      5.34
32                      5.07
64                      5.54
128                     5.62
256                     7.04
512                     6.17
1024                    6.40
2048                    8.24
4096                   10.99
8192                   15.61
16384                  25.49
32768                 278.69
65536                 738.60
131072               1459.13
262144               3751.97
524288               7145.94
1048576             10727.27
```

</details>

Let's run point to point latency now. Use the same `$binds`.

```bash
# Singularity Container
flux run -N2 -n 2 -o cpu-affinity=per-task singularity exec --bind ${binds} --env UCX_TLS=ib --env UCX_NET_DEVICES=mlx5_ib0:1 ./flux-tutorials_azurehpc-2204-osu.sif /bin/bash -c ". /source-hpcx.sh && hpcx_load && /opt/osu-benchmark/build.openmpi/mpi/pt2pt/osu_latency"

# Bare Metal
flux run -N2 -n 2 -o cpu-affinity=per-task --env UCX_TLS=ib --env UCX_NET_DEVICES=mlx5_ib0:1 /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency
```

<details>

<summary>OSU Latency on Bare Metal vs. Singularity</summary>

```console
# Singularity container
# OSU MPI Latency Test v5.8
# Size          Latency (us)
0                       1.63
1                       1.62
2                       1.62
4                       1.63
8                       1.63
16                      1.63
32                      1.77
64                      1.83
128                     1.87
256                     2.37
512                     2.45
1024                    2.59
2048                    2.77
4096                    3.52
8192                    4.02
16384                   5.31
32768                   7.07
65536                   9.51
131072                 13.79
262144                 17.52
524288                 28.61
1048576                49.71
2097152                92.27
4194304               177.59

# Bare Metal VM
```

</details>

### 7. LAMMPS-REAX

Now pull lammps

```bash
flux exec --rank 0-1 singularity pull docker://ghcr.io/converged-computing/flux-tutorials:azurehpc-2204-lammps-reax
```

And run, with the same binds, again using the container and bare metal.

```bash
binds=/opt/hpcx-v2.15-gcc-MLNX_OFED_LINUX-5-ubuntu22.04-cuda12-gdrcopy2-nccl2.17-x86_64/:/opt/hpcx-v2.19-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64

# Singularity Container
# 99.9% CPU use with 192 MPI tasks x 1 OpenMP threads
# Total wall time: 0:01:07
flux run -o cpu-affinity=per-task -N2 -n 192 singularity exec --bind ${binds} --env UCX_TLS=all --env UCX_NET_DEVICES=mlx5_ib0:1 --pwd /code ./flux-tutorials_azurehpc-2204-lammps-reax.sif /bin/bash -c ". /source-hpcx.sh && hpcx_load && /usr/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxff.hns -nocite"

# Bare Metal VM
# 100.0% CPU use with 192 MPI tasks x 1 OpenMP threads
# Total wall time: 0:01:07
cd /tmp/lammps/examples/reaxff/HNS/
flux run -o cpu-affinity=per-task -N2 -n 192 --env UCX_TLS=all --env UCX_NET_DEVICES=mlx5_ib0:1 /usr/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxff.hns -nocite
```

They are exactly the same, and `UCX_TLS` doesn't seem to matter, but likely you want to adjust/tweak to your liking.

### 8. Install Usernetes

Since we can't get the private address space to work, we use the instance public IPs here. This is not ideal, but will work for the time being.

#### Bring up the control plane

For the first argument, this is the ranks list to go to flux archive -> flux exec. For example, if broker 2 is up you'd provide "2." If a range between 2 and 10 is up, you'd provide "2-10"

```console
ip_address=$(az vmss list-instance-public-ips -g terraform-testing -n flux | jq -r .[0].ipAddress)
scp -i ./id_azure ./install/start_control_plane.sh azureuser@${ip_address}:/tmp/start_control_plane.sh
ssh -i ./id_azure azureuser@${ip_address} "/bin/bash /tmp/start_control_plane.sh 1"
```

#### Bring up workers

```console
# This goes through all addresses except for the first
sed '1d' hosts.txt > workers.txt
for address in $(cat workers.txt)
  do
     scp -i ./id_azure ./install/start_worker.sh ${address}:/tmp/start_worker.sh
done
pssh -h workers.txt -x "-i ./id_azure" "/bin/bash /tmp/start_worker.sh"
```

#### Finish control plane

This last command runs the sync-external-ip command. The `ip_address` variable should still be defined to have the lead broker address.

```console
scp -i ./id_azure ./install/finish_control_plane.sh azureuser@${ip_address}:/tmp/finish_control_plane.sh
ssh -i ./id_azure azureuser@${ip_address} "/bin/bash /tmp/finish_control_plane.sh"
```

### 9. Install the Flux Operator

From the lead broker, install the flux operator:

```bash
ssh -i ./id_azure azureuser@${ip_address}
```
```bash
# enable auto-completion
source <(kubectl completion bash)

kubectl apply -f https://raw.githubusercontent.com/flux-framework/flux-operator/refs/heads/main/examples/dist/flux-operator.yaml

# Check that it's running OK
kubectl logs -n operator-system operator-controller-manager-69cdcdb9ff-cmrmd 
```

### 10. Expose infiniband 

Note that while we don't see `ib0` in the usernetes nodes, infiniband is present (look at `/dev/infiniband`). This means we can skip the driver install and just install the daemonset that will expose the labels. It also means we need to update the configmap.yaml we use for the daemonset. Here is how to do that.

```bash
# On the lead broker
git clone https://github.com/converged-computing/aks-infiniband-install
cd aks-infiniband-install
kubectl apply -k ./daemonset-usernetes/
```

Check that the node(s) are now annotated.

```bash
$ kubectl  get nodes -o json | jq -r .items[].status.capacity
```
```console
...
{
  "cpu": "96",
  "ephemeral-storage": "101430960Ki",
  "hugepages-1Gi": "0",
  "hugepages-2Mi": "0",
  "mellanox.com/shared_hca_rdma": "1",
  "memory": "470536548Ki",
  "pods": "110"
}
```

### 11. Run Applications

From the cloud shell (or your local machine), let's copy  over the yaml configs (we can eventually change this to wget).

```bash
ip_address=$(az vmss list-instance-public-ips -g terraform-testing -n flux | jq -r .[0].ipAddress)
scp -i ./id_azure ./examples/minicluster-lammps.yaml azureuser@${ip_address}:/home/azureuser/lammps.yaml
```

Then on the lead broker virtual machine:

```bash
kubectl apply -f lammps.yaml
kubectl exec -it flux-sample-0-xxx -- bash
```

This will create an interactive cluster to shell into - you can ignore the bash errors (there is a path in the source that will work for the Singularity container when a slightly different path is bound from the host). First, connect to the flux broker, and once you are connected to the instance, test with `flux resource list`.

```bash
flux proxy local:///mnt/flux/view/run/flux/local bash
```

Now source the MPI environment - this is for multi-threaded init:

```bash
. /opt/hpcx-v2.19-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64/hpcx-mt-init.sh 
hpcx_load
```

This is helpful for debugging, if needed.

```bash
apt-get install -y ibverbs-utils
```

Now let's run lammps!

```bash
# We are already in /opt/lammps/examples/reaxff/HNS 
# This should work (one node with ib and shared memory)
flux run -o cpu-affinity=per-task -N1 -n 96 --env UCX_TLS=ib,sm --env UCX_NET_DEVICES=mlx5_ib0:1 lmp -v x 1 -v y 1 -v z 1 -in in.reaxff.hns -nocite

/opt/hpcx-v2.19-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64/hpcx-rebuild/lib:/opt/hpcx-v2.19-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64/hcoll/lib
flux run -o cpu-affinity=per-task -N2 -n 192 --env OMPI_MPI_mca_coll_hcoll_enable=0 --env OMPI_MPI_mca_coll_ucc_enable=0 --env UCX_TLS=ib --env UCX_NET_DEVICES=mlx5_ib0:1 lmp -v x 1 -v y 1 -v z 1 -in in.reaxff.hns -nocite


# -x UCC_LOG_LEVEL=debug -x UCC_TLS=ucp
flux run -o cpu-affinity=per-task -N2 -n 192 --env UCC_LOG_LEVEL=info --env UCC_TLS=ucp --env UCC_CONFIG_FILE= -OMPI_MPI_mca_coll_ucc_enable=0  --env UCX_TLS=dc_x --env UCX_NET_DEVICES=mlx5_ib0:1 lmp -v x 1 -v y 1 -v z 1 -in in.reaxff.hns -nocite
```

The time above is

### 12. Cleanup

When you are done:

```bash
make destroy
```

But if not, you can either delete the resource group from the console, or the command line:

```bash
az group delete --name terraform-testing
```

