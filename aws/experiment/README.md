# Flux Usernetes Experiment on AWS

Note that we re-did the osu all reduce on 2 nodes in [final/osu-followup](final/osu-followup)

### Lammps and OSU Benchmarks

- Start time: 6:51am
- Done creation time: 6:54am
- End time:~6:00pm
- hpc7g.4xlarge x 33
- Estimated compute cost: $56 per hour.

$1.70 * 33 * 13 hours 24 minutes.

Topology for later:

```bash
aws ec2 describe-instance-topology --region us-east-1 --filters Name=instance-type,Values=hpc7g.4xlarge > topology-33.json
aws ec2 describe-instances --filters "Name=instance-type,Values=hpc7g.4xlarge" --region us-east-1 > instances-33.json
```

## LAMMPS

```bash
cd /home/ubuntu/lammps
mkdir -p ./results/bare-metal
```

Runs across sizes for each of the following:

- 32, 512
- 16, 256
- 8, 128
- 4, 64

```console
screen /bin/bash
for i in $(seq 1 20); do 
    echo "Running iteration $i"
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/bare-metal/lammps-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/bare-metal/lammps-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/bare-metal/lammps-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/bare-metal/lammps-4-64-${i}.out
done
```

Now container runs for lammps. This container needs a pull to all nodes.

```bash
cd /home/ubuntu/lammps
flux exec --rank all --dir /home/ubuntu/lammps singularity pull docker://ghcr.io/rse-ops/lammps-efa:ubuntu-22.04
container=/home/ubuntu/lammps/lammps-efa_ubuntu-22.04.sif

# Create output directory for results
mkdir -p ./results/container
```

And the experiments!

```console
# Run the same loop, but in the container
for i in $(seq 1 20); do 
    echo "Running iteration $i"
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/container/lammps-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/container/lammps-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/container/lammps-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/container/lammps-4-64-${i}.out
done
```

You can sanity check each of the above as you go - there should be 80 files in each directory.
Now we are going to switch over the osu to run on bare metal, before we start usernetes.

```bash
# This is where the example is
flux exec --rank all mkdir -p /home/ubuntu/osu
cd /home/ubuntu/osu

# Create output directory for results
mkdir -p ./results/bare-metal
flux exec --rank all -x 0 mkdir -p /home/ubuntu/osu
```

And run the experiments:

```bash
for i in $(seq 1 20); do 
    echo "Running iteration $i"
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce  |& tee ./results/bare-metal/all_reduce-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce  |& tee ./results/bare-metal/all_reduce-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce  |& tee ./results/bare-metal/all_reduce-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce  |& tee ./results/bare-metal/all_reduce-4-64-${i}.out
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_barrier  |& tee ./results/bare-metal/osu_barrier-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_barrier  |& tee ./results/bare-metal/osu_barrier-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_barrier  |& tee ./results/bare-metal/osu_barrier-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_barrier  |& tee ./results/bare-metal/osu_barrier-4-64-${i}.out
    flux run -N 2 --ntasks 2 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency  |& tee ./results/bare-metal/osu_latency-${i}.out
    flux run -N 2 --ntasks 2 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw  |& tee ./results/bare-metal/osu_bw-${i}.out
done
```

Now let's run the same OSU benchmarks with a container.

```bash
flux exec --rank all --dir /home/ubuntu/osu singularity pull docker://ghcr.io/rse-ops/osu-benchmarks-efa:ubuntu-22.04
container=/home/ubuntu/osu/osu-benchmarks-efa_ubuntu-22.04.sif

# Create output directory for results
mkdir -p ./results/container
```

Now the experiment loop again

```console
for i in $(seq 1 20); do 
    echo "Running iteration $i"
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task singularity exec $container osu_allreduce |& tee ./results/container/all_reduce-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task singularity exec $container osu_allreduce |& tee ./results/container/all_reduce-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task singularity exec $container osu_allreduce |& tee ./results/container/all_reduce-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task singularity exec $container osu_allreduce |& tee ./results/container/all_reduce-4-64-${i}.out
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task singularity exec $container osu_barrier |& tee ./results/container/osu_barrier-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task singularity exec $container osu_barrier |& tee ./results/container/osu_barrier-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task singularity exec $container osu_barrier |& tee ./results/container/osu_barrier-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task singularity exec $container osu_barrier |& tee ./results/container/osu_barrier-4-64-${i}.out
    flux run -N 2 --ntasks 2 -c 1 -o cpu-affinity=per-task singularity exec $container osu_latency |& tee ./results/container/osu_latency-${i}.out
    flux run -N 2 --ntasks 2 -c 1 -o cpu-affinity=per-task singularity exec $container osu_bw |& tee ./results/container/osu_bw-${i}.out
done
```

Now we've finished running lammps on bare metal (with and without containers) and the same for OSU (with and without containers) we can bring up usernetes to run lammps and osu there.

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
flux exec -x 0 -r all --dir /home/ubuntu/usernetes /bin/bash ./start-worker.sh
```

I sourced my bash profile and then ensured I had my nodes, and saved them too.

```bash
. ~/.bashrc
kubectl get nodes
```
```console
NAME                      STATUS   ROLES           AGE   VERSION
u7s-i-001a283495908a2fd   Ready    <none>          31s   v1.29.1
u7s-i-009a06272fa6f2058   Ready    <none>          30s   v1.29.1
u7s-i-00f719a743be592a5   Ready    <none>          31s   v1.29.1
u7s-i-011e630ae380a3902   Ready    <none>          31s   v1.29.1
u7s-i-016e02971902bd653   Ready    <none>          30s   v1.29.1
u7s-i-0301cce2b29265928   Ready    <none>          30s   v1.29.1
u7s-i-039696d8f2441c950   Ready    <none>          31s   v1.29.1
u7s-i-04baab5d1bbc299d0   Ready    <none>          31s   v1.29.1
u7s-i-04c715913d9e3c8b7   Ready    <none>          30s   v1.29.1
u7s-i-050e13126f196ccda   Ready    <none>          31s   v1.29.1
u7s-i-05342cddb1d5e588a   Ready    control-plane   99s   v1.29.1
u7s-i-05753c08c69e09b89   Ready    <none>          31s   v1.29.1
u7s-i-05fdfe9cfe36a2d9c   Ready    <none>          31s   v1.29.1
u7s-i-076a2e863985642dc   Ready    <none>          28s   v1.29.1
u7s-i-07734cd953035619e   Ready    <none>          31s   v1.29.1
u7s-i-07749c75466498890   Ready    <none>          31s   v1.29.1
u7s-i-07de982c53a7e1269   Ready    <none>          30s   v1.29.1
u7s-i-08433ac2eace66b76   Ready    <none>          31s   v1.29.1
u7s-i-0851f99a0032ba34f   Ready    <none>          31s   v1.29.1
u7s-i-0945536058914df26   Ready    <none>          31s   v1.29.1
u7s-i-09549f380dde16c05   Ready    <none>          31s   v1.29.1
u7s-i-096750f3a493af595   Ready    <none>          31s   v1.29.1
u7s-i-0a9ecc9961ce70c53   Ready    <none>          31s   v1.29.1
u7s-i-0af3fd8b505544f7c   Ready    <none>          31s   v1.29.1
u7s-i-0c6fc8a4eea611507   Ready    <none>          31s   v1.29.1
u7s-i-0c8c7a993d84cb710   Ready    <none>          31s   v1.29.1
u7s-i-0d2ee70154833869a   Ready    <none>          41s   v1.29.1
u7s-i-0dc37689ac509d306   Ready    <none>          31s   v1.29.1
u7s-i-0e7dcc1113c94786c   Ready    <none>          31s   v1.29.1
u7s-i-0ec8879f3eb417a40   Ready    <none>          30s   v1.29.1
u7s-i-0f1874ca8accbadbc   Ready    <none>          29s   v1.29.1
u7s-i-0fb43e637f1433f4b   Ready    <none>          31s   v1.29.1
u7s-i-0fd32d4b4de9a52fc   Ready    <none>          30s   v1.29.1
```
```bash
kubectl get nodes -o json > ../osu/results/nodes-33.json
```

Now let's prepare the operator.


```bash
# Autocomplete
source <(kubectl completion bash) 
```

Clone the repository with configs, etc.

```bash
# Note that at the time of running, this was the experiment-june-1 branch, now is in main
git clone https://github.com/converged-computing/flux-usernetes /home/ubuntu/lammps/flux-usernetes

# This is run from /home/ubuntu/lammps
kubectl apply -f ./flux-usernetes/aws/examples/lammps/crd/efa-device-plugin.yaml 
kubectl apply -f ./flux-usernetes/aws/examples/lammps/crd/flux-operator-arm.yaml

# Make sure it's running
kubectl logs -n operator-system operator-controller-manager-547869d677-8pqmt 
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

Change to full size and run once to pull containers (so our actual runs don't need to do that)

```bash
# Run once to pull containers to nodes (this will be thrown away)
kubectl apply -f ./minicluster-efa.yaml
kubectl delete -f ./minicluster-efa.yaml
```

Note that I did `kubectl get pods -o wide` to sanity check we had an assignment of one pod per node (we did)!
Now we will need to run for each size mentioned in the experiment file:

```
# sizes for experiment:
# 32, 512
# 16, 256
# 8, 128
# 4, 64
```

To be clear, you need to change the size in the minicluster-efa.yaml for each of the above, coordinated with the loop below (which is saving the result to that path).

```bash
size=4
tasks=64
for i in $(seq 1 20); do 
    echo "Running iteration ${i}"
    kubectl apply -f ./minicluster-efa.yaml 
    sleep 10
    pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)
    echo "Lead broker pod is ${pod}"
    # Wait for init to finish and pod to initialize
    kubectl wait --for=condition=ready --timeout=120s pod/${pod}
    sleep 10
    # This waits for lammps to finish (streaming the log)
    kubectl logs ${pod} -f |& tee ./results/usernetes/lammps-${size}-${tasks}-${i}.out
    # And an extra precaution the entire job/workers are complete
    kubectl wait --for=condition=complete --timeout=120s job/flux-sample-efa
    kubectl delete -f ./minicluster-efa.yaml --wait=true
done
```

Now let's run the benchmarks in kubernetes (usernetes).


```console
cd /home/ubuntu/osu
cp -R ../lammps/flux-usernetes/aws/examples/osu-benchmarks/crd ./crd
```

Now let's run the experiments in Usernetes. For each minicluster, you'll need to tweak the size,
but the experiments (barrier, allreduce, etc) are provided separately.

```bash
# Create output directory for results
mkdir -p ./results/usernetes

# Run one to pull the container to all nodes
kubectl apply -f ./crd/minicluster-efa-all-reduce.yaml
kubectl delete -f ./crd/minicluster-efa-all-reduce.yaml
```

```bash
# Do this for each size 32, 16, 8, and 4 (it gets faster)
# YOU WILL NEED TO CHANGE THE SIZE IN THE MINICLUSTERS YAML FILES
# Note that we can comment out the last section (latency) after the first 20 runs.
size=4
for i in $(seq 1 20); do 
    echo "Running iteration ${i}"
    kubectl apply -f ./crd/minicluster-efa-all-reduce.yaml
    sleep 10
    pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)
    echo "Lead broker pod is ${pod}"
    kubectl wait --for=condition=ready --timeout=120s pod/${pod}
    sleep 10
    kubectl logs ${pod} -f |& tee ./results/usernetes/osu-all-reduce-${size}-${i}.out
    kubectl delete -f ./crd/minicluster-efa-all-reduce.yaml 

    kubectl apply -f ./crd/minicluster-efa-barrier.yaml
    sleep 10
    pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)
    echo "Lead broker pod is ${pod}"
    kubectl wait --for=condition=ready --timeout=120s pod/${pod}
    sleep 10
    kubectl logs ${pod} -f |& tee ./results/usernetes/osu-barrier-${size}-${i}.out
    kubectl delete -f ./crd/minicluster-efa-barrier.yaml

    kubectl apply -f ./crd/minicluster-efa-osu-latency.yaml
    sleep 10
    pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)
    echo "Lead broker pod is ${pod}"
    kubectl wait --for=condition=ready --timeout=120s pod/${pod}
    sleep 10
    kubectl logs ${pod} -f |& tee ./results/usernetes/osu-latency-${size}-${i}.out
    kubectl delete -f ./crd/minicluster-efa-osu-latency.yaml

    kubectl apply -f ./crd/minicluster-efa-osu-bw.yaml
    sleep 10
    pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)
    echo "Lead broker pod is ${pod}"
    kubectl wait --for=condition=ready --timeout=120s pod/${pod}
    sleep 10
    kubectl logs ${pod} -f |& tee ./results/usernetes/osu-bw-${size}-${i}.out
    kubectl delete -f ./crd/minicluster-efa-osu-bw.yaml
done
```

After this, we go back and run the initial bare metal runs again, for lammps and osu benchmarks. The difference is that we have usernetes running in the background.

```bash
cd /home/ubuntu/lammps
mkdir -p ./results/bare-metal-with-usernetes
for i in $(seq 1 20); do 
    echo "Running iteration $i"
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/bare-metal-with-usernetes/lammps-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/bare-metal-with-usernetes/lammps-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/bare-metal-with-usernetes/lammps-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/bare-metal-with-usernetes/lammps-4-64-${i}.out
done
```

Now container runs for lammps.

```bash
container=/home/ubuntu/lammps/lammps-efa_ubuntu-22.04.sif
mkdir -p ./results/container-with-usernetes

# Run the same loop, but in the container
for i in $(seq 1 20); do 
    echo "Running iteration $i"
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/container-with-usernetes/lammps-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/container-with-usernetes/lammps-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/container-with-usernetes/lammps-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task singularity exec $container /usr/bin/lmp -v x 16 -v y 16 -v z 8 -in ./in.reaxff.hns -nocite |& tee ./results/container-with-usernetes/lammps-4-64-${i}.out
done
```

Do the same for OSU, on bare metal, with and without a container.

```bash
cd /home/ubuntu/osu
mkdir -p ./results/bare-metal-with-usernetes
for i in $(seq 1 20); do 
    echo "Running iteration $i"
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce  |& tee ./results/bare-metal-with-usernetes/all_reduce-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce  |& tee ./results/bare-metal-with-usernetes/all_reduce-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce  |& tee ./results/bare-metal-with-usernetes/all_reduce-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce  |& tee ./results/bare-metal-with-usernetes/all_reduce-4-64-${i}.out
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_barrier  |& tee ./results/bare-metal-with-usernetes/osu_barrier-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_barrier  |& tee ./results/bare-metal-with-usernetes/osu_barrier-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_barrier  |& tee ./results/bare-metal-with-usernetes/osu_barrier-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_barrier  |& tee ./results/bare-metal-with-usernetes/osu_barrier-4-64-${i}.out
    flux run -N 2 --ntasks 2 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency  |& tee ./results/bare-metal-with-usernetes/osu_latency-${i}.out
    flux run -N 2 --ntasks 2 -c 1 -o cpu-affinity=per-task /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw |& tee ./results/bare-metal-with-usernetes/osu_bw-${i}.out
done
```

Now let's run the same OSU benchmarks with a container.

```bash
container=/home/ubuntu/osu/osu-benchmarks-efa_ubuntu-22.04.sif

# Create output directory for results
mkdir -p ./results/container-with-usernetes
```

Now the experiment loop again

```console
for i in $(seq 1 20); do 
    echo "Running iteration $i"
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task singularity exec $container osu_allreduce  |& tee ./results/container-with-usernetes/all_reduce-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task singularity exec $container osu_allreduce  |& tee ./results/container-with-usernetes/all_reduce-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task singularity exec $container osu_allreduce  |& tee ./results/container-with-usernetes/all_reduce-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task singularity exec $container osu_allreduce  |& tee ./results/container-with-usernetes/all_reduce-4-64-${i}.out
    flux run -N 32 --ntasks 512 -c 1 -o cpu-affinity=per-task singularity exec $container osu_barrier  |& tee ./results/container-with-usernetes/osu_barrier-32-512-${i}.out
    flux run -N 16 --ntasks 256 -c 1 -o cpu-affinity=per-task singularity exec $container osu_barrier  |& tee ./results/container-with-usernetes/osu_barrier-16-256-${i}.out
    flux run -N 8 --ntasks 128 -c 1 -o cpu-affinity=per-task singularity exec $container osu_barrier  |& tee ./results/container-with-usernetes/osu_barrier-8-128-${i}.out
    flux run -N 4 --ntasks 64 -c 1 -o cpu-affinity=per-task singularity exec $container osu_barrier |& tee ./results/container-with-usernetes/osu_barrier-4-64-${i}.out
    flux run -N 2 --ntasks 2 -c 1 -o cpu-affinity=per-task singularity exec $container osu_latency |& tee ./results/container-with-usernetes/osu_latency-${i}.out
    flux run -N 2 --ntasks 2 -c 1 -o cpu-affinity=per-task singularity exec $container osu_bw |& tee ./results/container-with-usernetes/osu_bw-${i}.out
done
```

Finally, let's run netmark once with usernetes (I copied this script from my local machine) and then on bare metal (with usernetes running) and then without. We don't have it installed on bare metal (without container) here, but we know the container performance == bare metal host, so it should be OK. First, prepare.


```bash
mkdir -p /home/ubuntu/netmark/results/container-usernetes
flux exec -r all --dir /home/ubuntu/netmark singularity pull docker://ghcr.io/rse-ops/netmark-efa:ubuntu-22.04
flux exec -r all -x 0 mkdir -p /home/ubuntu/netmark/results/container-usernetes
cd /home/ubuntu/netmark/results/container-usernetes
container=/home/ubuntu/netmark/netmark-efa_ubuntu-22.04.sif 
```

Here is bare metal with usernetes running (this should be the fastest). My flux install broke and I had to think on my feet to use mpirun.

```bash
# I was originally going to try this:
flux run -N 32 -ntasks 512 singularity exec $container /usr/local/bin/netmark.x -w 10 -t 20 -c 20 -b 0 -s

# But the above seems like it would take impossibly long? Instead I did (hoping to control 1 task per node)
flux run -N 32 --tasks-per-node 1 singularity exec --workdir /home/ubuntu/netmark/results/container-usernetes $container /usr/local/bin/netmark.x -w 10 -t 20 -c 20 -b 0 -s
```

This is the usernetes run. We do it interactively and will copy the results files to the host

```bash
kubectl apply -f ./netmark-efa.yaml 
kubectl exec -it flux-sample-efa-0-xxxx bash
flux proxy local:///mnt/flux/view/run/flux/local bash
flux resource list
```

Then run netmark, let's created a scoped output directory.

```bash
mkdir /opt/netmark
cd /opt/netmark
flux run -N 32 --tasks-per-node 1 netmark.x -w 10 -t 20 -c 20 -b 0 -s
```

In a different terminal, copy out the results.

```bash
kubectl cp flux-sample-efa-0-xxxx:/opt/netmark ./results/usernetes
```

When you are done, we need to bring down the usernetes nodes.

```
cd ~/usernetes
flux exec -r all --dir /home/ubuntu/usernetes make down
```

Then one more run of container:

```bash
flux exec -r all -x 0 mkdir -p /home/ubuntu/netmark/results/container
mkdir -p /home/ubuntu/netmark/results/container
cd /home/ubuntu/netmark/results/container
container=/home/ubuntu/netmark/netmark-efa_ubuntu-22.04.sif 
flux run -N 32 --tasks-per-node 1 singularity exec --workdir /home/ubuntu/netmark/results/container $container /usr/local/bin/netmark.x -w 10 -t 20 -c 20 -b 0 -s
```

I couldn't get the full output but I saved the screen stream to file. It's better than nothing.
And then you are done! Copy the data, or you will be very sad. I did this at several increments, mostly worried about losing data.
And some extra flux info:

```
$ flux resource info
33 Nodes, 528 Cores, 0 GPUs
{"version": 1, "execution": {"R_lite": [{"rank": "0-32", "children": {"core": "0-15"}}], "starttime": 0.0, "expiration": 0.0, "nodelist": ["i-05342cddb1d5e588a,i-04c715913d9e3c8b7,i-05fdfe9cfe36a2d9c,i-076a2e863985642dc,i-0c8c7a993d84cb710,i-09549f380dde16c05,i-07749c75466498890,i-07734cd953035619e,i-016e02971902bd653,i-05753c08c69e09b89,i-0851f99a0032ba34f,i-07de982c53a7e1269,i-0fd32d4b4de9a52fc,i-0fb43e637f1433f4b,i-0a9ecc9961ce70c53,i-001a283495908a2fd,i-00f719a743be592a5,i-050e13126f196ccda,i-0c6fc8a4eea611507,i-096750f3a493af595,i-011e630ae380a3902,i-0af3fd8b505544f7c,i-0301cce2b29265928,i-009a06272fa6f2058,i-0ec8879f3eb417a40,i-0945536058914df26,i-0e7dcc1113c94786c,i-0dc37689ac509d306,i-039696d8f2441c950,i-08433ac2eace66b76,i-0f1874ca8accbadbc,i-04baab5d1bbc299d0,i-0d2ee70154833869a"]}}
```

To plot results for LAMMPS

```bash
python plot-lammps.py
```
```console
                           ranks iteration time_seconds  nodes percent_cpu_utilization
experiment                                                                            
bare-metal                 240.0      10.5         41.8   15.0                   99.65
bare-metal-with-usernetes  240.0      10.5       42.625   15.0                99.46875
container                  240.0      10.5       42.225   15.0                99.65125
container-with-usernetes   240.0      10.5      42.7375   15.0                99.46375
usernetes                  240.0      10.5       128.05   15.0                    43.7
                                ranks  iteration  time_seconds      nodes  percent_cpu_utilization
experiment                                                                                        
bare-metal                 172.663425   5.802662     25.978764  10.791464                 0.111378
bare-metal-with-usernetes  172.663425   5.802662     25.475913  10.791464                 0.110915
container                  172.663425   5.802662     25.573411  10.791464                 0.110228
container-with-usernetes   172.663425   5.802662     25.492488  10.791464                 0.110515
usernetes                  172.663425   5.802662     62.431715  10.791464                 0.000000
```
### Network Hints

Here is ifconfig from inside of a usernetes container - not the mtu is not very high. We might need to adjust that to get higher bandwidth?

```console
cni0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1450
        inet 10.244.0.1  netmask 255.255.255.0  broadcast 10.244.0.255
        ether fa:17:4a:58:94:4e  txqueuelen 1000  (Ethernet)
        RX packets 854020  bytes 158257769 (150.9 MiB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 853446  bytes 222712762 (212.3 MiB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 10.100.192.2  netmask 255.255.255.0  broadcast 10.100.192.255
        ether 02:42:0a:64:c0:02  txqueuelen 0  (Ethernet)
        RX packets 2892606  bytes 541187094 (516.1 MiB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 2779507  bytes 2830131302 (2.6 GiB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

flannel.1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1450
        inet 10.244.0.0  netmask 255.255.255.255  broadcast 0.0.0.0
        ether 6a:72:b9:d4:df:da  txqueuelen 0  (Ethernet)
        RX packets 727287  bytes 81508580 (77.7 MiB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 727285  bytes 148897407 (141.9 MiB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        loop  txqueuelen 1000  (Local Loopback)
        RX packets 7892199  bytes 4703611753 (4.3 GiB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 7892199  bytes 4703611753 (4.3 GiB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

veth5a961ca5: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1450
        ether e2:d5:2e:b9:9b:b3  txqueuelen 0  (Ethernet)
        RX packets 427236  bytes 85147636 (81.2 MiB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 426221  bytes 111330451 (106.1 MiB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

veth860aee4a: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1450
        ether 82:24:d8:57:23:cb  txqueuelen 0  (Ethernet)
        RX packets 426785  bytes 85066455 (81.1 MiB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 427306  bytes 111388109 (106.2 MiB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

Here is ifconfig from the outside:

```bash
docker0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        inet 172.17.0.1  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:42:59:da:10:a2  txqueuelen 0  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

ens5: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 9001
        inet 10.0.1.37  netmask 255.255.255.0  broadcast 10.0.1.255
        inet6 fe80::c31:38ff:fe75:676b  prefixlen 64  scopeid 0x20<link>
        ether 0e:31:38:75:67:6b  txqueuelen 1000  (Ethernet)
        RX packets 22219580  bytes 50893779381 (50.8 GB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 15194370  bytes 41824420284 (41.8 GB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        inet6 ::1  prefixlen 128  scopeid 0x10<host>
        loop  txqueuelen 1000  (Local Loopback)
        RX packets 61818  bytes 39471814 (39.4 MB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 61818  bytes 39471814 (39.4 MB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

Note the MTU. I'm not sure we can compete with that (1450 vs a minimum of 9001).


### Machine Learning Hybrid Example

Bring up the main.tf with:

 - size 5 nodes for a size 4 cluster (we don't need any kind of scale here to demonstrate it working).
 
```bash
cd ~/usernetes
```

Update the docker-compose.yaml

```console
wget -O docker-compose-ml.yaml https://raw.githubusercontent.com/converged-computing/flux-usernetes/main/aws/examples/ml-server/crd/docker-compose.yaml
flux archive create --name=docker-compose --mmap -C /home/ubuntu/usernetes docker-compose-ml.yaml
flux exec -x 0 -r all flux archive extract --name=docker-compose -C /home/ubuntu/usernetes
flux exec -r all --dir /home/ubuntu/usernetes mv docker-compose-ml.yaml docker-compose.yaml
```

And then start usernetes, the control plane then workers (from the control plane, nice)!

```bash
./start-control-plane.sh
flux archive create --name=join-command --mmap -C /home/ubuntu/usernetes join-command
flux exec -x 0 -r all flux archive extract --name=join-command -C /home/ubuntu/usernetes
flux exec -x 0 -r all --dir /home/ubuntu/usernetes /bin/bash ./start-worker.sh
. ~/.bashrc
kubectl get nodes

# Autocomplete
source <(kubectl completion bash) 
```

Deploy the machine learning server.

```bash
cd /home/ubuntu/lammps
kubectl  apply -f flux-usernetes/aws/examples/ml-server/crd/server-deployment.yaml
```

This is how to get the host:

```bash
kubectl  get pods -o wide
```
```console
NAME                         READY   STATUS    RESTARTS   AGE     IP           NODE                      NOMINATED NODE   READINESS GATES
ml-server-6547db94fd-qjwkb   1/1     Running   0          6m32s   10.244.1.5   u7s-i-0ba186b66890a2230   <none>           <none>
```
```bash
host=http://i-0be4941438656344d:8080
curl -k $host/api/ | jq
```
```console
{
  "id": "django_river_ml",
  "status": "running",
  "name": "Django River ML Endpoint",
  "description": "This service provides an api for models",
  "documentationUrl": "https://vsoch.github.io/django-river-ml",
  "storage": "shelve",
  "river_version": "0.21.0",
  "version": "0.0.21"
}
```

Create three empty models, different kinds of regressions. This is container that has river packaged we can use as a client.

```bash
flux exec -r all --dir /home/ubuntu/lammps singularity pull docker://ghcr.io/converged-computing/lammps-stream-ml:lammps-arm
```

Here is how to create the models for the running server. The names will be funny but largely don't matter - we can get them programmatically later.

```bash
# Remember, we need to run this from the lammps root!
cd /home/ubuntu/lammps

# Set the container path
container=/home/ubuntu/lammps/lammps-stream-ml_lammps-arm.sif

# Install the riverapi for local interaction
python3 -m pip install riverapi 

# the host should be set in the environment, $host
echo $host

# Assumes service running on localhost directory (first parameter, default)
singularity exec $container python3 /code/1-create-models.py $host
```
```console
Preparing to create models for client URL http://i-0c79705f628c562a3:8080
Created model expressive-cupcake
Created model confused-underoos
Created model doopy-platanos
```

### Train lammps

Copy the script into the lammps directory, for easy access.

```bash
cp ./flux-usernetes/aws/examples/ml-server/docker/scripts/2-run-lammps-flux.py .
```

Run jobs with flux (train), 1000 samples, for 4 nodes and up to 8x8x8.

```bash
# screen so we don't lose stuff
screen /bin/bash
time python3 2-run-lammps-flux.py train --container $container --np 64 --nodes 4 --workdir /opt/lammps/examples/reaxff/HNS --x-min 1 --x-max 8 --y-min 1 --y-max 8 --z-min 1 --z-max 8 --iters 1000 --url $host
```

Note that training took 146 minutes:

```console
  Training quirky-rabbit with {'x': 8, 'y': 3, 'z': 2} to predict 4
  Training swampy-knife with {'x': 8, 'y': 3, 'z': 2} to predict 4

real    146m11.027s
user    1m34.516s
sys     0m20.570s
```

### Predict LAMMPS

Now let's generate more data, but this time, compare the actual time with each model prediction. This script is very similar but calls a different API function.

```bash
python3 2-run-lammps-flux.py predict --container $container --np 64 --nodes 4 --workdir /opt/lammps/examples/reaxff/HNS --x-min 1 --x-max 8 --y-min 1 --y-max 8 --z-min 1 --z-max 8 --iters 250 --url $host --out test-predict.json
```
```console
🧪️ Running iteration 0
/usr/bin/mpirun -N 1 --ppn 4 /usr/bin/lmp -v x 5 y 5 z 7 -log /tmp/lammps.log -in in.reaxc.hns -nocite
  Predicted value for confused-underoos with {'x': 5, 'y': 5, 'z': 7} is 29.434425573805264
  Predicted value for doopy-platanos with {'x': 5, 'y': 5, 'z': 7} is 45.12076412968298
  Predicted value for expressive-cupcake with {'x': 5, 'y': 5, 'z': 7} is 23.273189928153677

🧪️ Running iteration 1
/usr/bin/mpirun -N 1 --ppn 4 /usr/bin/lmp -v x 6 y 3 z 3 -log /tmp/lammps.log -in in.reaxc.hns -nocite
  Predicted value for confused-underoos with {'x': 3, 'y': 3, 'z': 3} is 14.937652338729954
  Predicted value for doopy-platanos with {'x': 3, 'y': 3, 'z': 3} is 24.11752143485609
  Predicted value for expressive-cupcake with {'x': 3, 'y': 3, 'z': 3} is 20.551130455244824

🧪️ Running iteration 2
/usr/bin/mpirun -N 1 --ppn 4 /usr/bin/lmp -v x 1 y 5 z 8 -log /tmp/lammps.log -in in.reaxc.hns -nocite
  Predicted value for confused-underoos with {'x': 5, 'y': 5, 'z': 8} is 31.7035947450996
  Predicted value for doopy-platanos with {'x': 5, 'y': 5, 'z': 8} is 47.583211665477734
  Predicted value for expressive-cupcake with {'x': 5, 'y': 5, 'z': 8} is 23.48086378670319
```

And then you'll run lammps for some number of iterations (defaults to 20) and calculate an metrics for each model.
Note that there are a lot of metrics you can see [here](https://riverml.xyz/latest/api/metrics/Accuracy/) (that's just a link to the first). The server itself also stores basic metrics, but we are doing this manually so it's a hold out test set.
Yes, these are quite bad, but it was only 20x for runs.

```console
ammps-arm.sif /usr/bin/lmp -v x 7 -v y 3 -v z 8 -log /tmp/lammps.log -in in.reaxff.hns -nocite
       result => Lammps run took 10 seconds
Model grated-ricecake predicts 11.04232057784137
Model quirky-rabbit predicts 16.345048556969655
Model swampy-knife predicts 8.781309553686834

⭐️ Performance for: grated-ricecake
          R Squared Error: 0.7918090116097876
       Mean Squared Error: 4.185888012573615
      Mean Absolute Error: 1.5499159478805307
  Root Mean Squared Error: 2.0459442838390336

⭐️ Performance for: quirky-rabbit
          R Squared Error: -0.5642529044232998
       Mean Squared Error: 31.450868896334878
      Mean Absolute Error: 5.189548235918719
  Root Mean Squared Error: 5.608107425534471

⭐️ Performance for: swampy-knife
          R Squared Error: 0.6045018869230796
       Mean Squared Error: 7.951885061524557
      Mean Absolute Error: 2.2032914541509716
  Root Mean Squared Error: 2.8199086973738274
```

Negative R squared, lol. 😬️ Let's save our models.


```bash
mkdir -p out
cd out
```
```python
from riverapi.main import Client

cli = Client('http://i-0be4941438656344d:8080')

# Download model as pickle
for model_name in cli.models()['models']:
    # Saves to model-name>.pkl in pwd unless you provide a second arg, dest
    cli.download_model(model_name)

# Also save metrics and stats
import json
results = {}
for model_name in cli.models()['models']:
    results[model_name] = {
        "model": cli.get_model_json(model_name),
        "stats": cli.stats(model_name),
        "metrics": cli.metrics(model_name)
    } 

with open('post-train-models.json', 'w') as fd:
    fd.write(json.dumps(results, indent=3))
```

