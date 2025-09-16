# Corona Experiments

Still need to do:
We are first going to create an allocation with some number of nodes, and run jobs on it.

## Cluster Setup

```bash
NODES=2
# Adjust time for hours needed
flux alloc -N $NODES --time 8h --bg

# This doesn't always work in format corona[N-M]
control_plane=$(flux job info $(flux job last) R | jq -r '.execution.nodelist[0]')
ssh $control_plane 
screen -S usernetes /bin/bash
systemctl --user start usernetes-control-plane
# Press Control + A + d

# Wait until finished, then ssh into each node and start service. It's okay to exit.
# This was the allocation for usernetes experiment, and pair to pair osu
# [219,221-223,228-230,232-244,255-259,261-267]

# This was final experiment cluster (running on premises and usernetes on same nodes)
# f4aQxvpHitUo pbatch   sochat1  flux        R     32     32   1.042h corona[188-189,192-194,196-207,213-214,219,221-230,232-233]

# Size 17 test
corona[189-190,192-194,196-207]

# here are worker nodes
flux job info $(flux job last) R | jq -r '.execution.nodelist[1:] | .[]' | while read -r worker_node; do
  echo $worker_node
done

ssh $worker_node
screen -S usernetes /bin/bash
systemctl --user start usernetes-worker
systemctl --user status usernetes-worker
# Press Control + A + d

# Back on control plane 
cd /tmp/sochat1/usernetes
. source_env.sh
make sync-external-ip
make install-flannel
```

## Experiments

### Bare Metal

#### LAMMPS

```bash
# size 4 at 16^3 problem size is 1:37
# size 32 at the same is 00:42
cd /usr/workspace/usernetes/experiments/lammps
export LD_LIBRARY_PATH=/usr/workspace/usernetes/lammps/build/install/lib64
mkdir -p ./results/lammps/4
mkdir -p ./results/lammps/8
mkdir -p ./results/lammps/16
mkdir -p ./results/lammps/32
for iter in $(seq 1 10)
    do
    flux run -N4 -n 192 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/4/lammps-$iter.out
    flux run -N8 -n 384 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/8/lammps-$iter.out
    flux run -N16 -n 768 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/16/lammps-$iter.out
    flux run -N32 -n 1536 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/32/lammps-$iter.out
done

# Test with numa
for iter in $(seq 1 10)
    do
    flux run -N4 -n 192 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite
done

# Test with singularity container equivalent - 21 seconds
cd /usr/workspace/usernetes/experiments/lammps
export OMPI_MCA_opal_warn_on_missing_libcuda=0
export OMPI_MCA_btl=^openib,tcp,self,vader
export OMPI_MCA_pml=ucx
export OMPI_MCA_osc=ucx
export UCX_NET_DEVICES=mlx5_0:1
export UCX_TLS=rc,sm,self
flux run -N16 -n 768 -opmi=pmix -o cpu-affinity=per-task singularity exec --pwd /data --bind /usr/workspace/usernetes/experiments/lammps:/data usernetes-python_lammps-flux-infiniband-openmpi-ucx-ubuntu2404.sif  lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite

# Testing up to size 16
mkdir -p ./results/lammps-16/4
mkdir -p ./results/lammps-16/8
mkdir -p ./results/lammps-16/16
for iter in $(seq 1 10)
    do
    flux run -N4 -n 192 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-16/4/lammps-$iter.out
    flux run -N8 -n 384 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-16/8/lammps-$iter.out
    flux run -N16 -n 768 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-16/16/lammps-$iter.out
done
```

#### OSU

```bash
cd /usr/workspace/usernetes/experiments/osu
mkdir -p ./results/osu/2
mkdir -p ./results/osu/4
mkdir -p ./results/osu/8
mkdir -p ./results/osu/16
mkdir -p ./results/osu/32
for iter in $(seq 1 10)
    do
    flux run -N4 -n 192 -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/collective/osu_allreduce |& tee ./results/osu/4/osu-allreduce-$iter.out
    flux run -N8 -n 384 -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/collective/osu_allreduce |& tee ./results/osu/8/osu-allreduce-$iter.out
    flux run -N16 -n 768 -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/collective/osu_allreduce |& tee ./results/osu/16/osu-allreduce-$iter.out
    flux run -N32 -n 1536 -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/collective/osu_allreduce |& tee ./results/osu/32/osu-allreduce-$iter.out
done
```

I did pairs separately.

```bash
mkdir -p ./results/osu/pairs

hosts=$(flux run -N 32 hostname | shuf -n 8 | tr '\n' ' ')
list=${hosts}

dequeue_from_list() {
  shift;
  list=$@
}

iter=0
for i in $hosts; do
  dequeue_from_list $list
  for j in $list; do
    echo "${i} ${j}"
    flux run --exclusive -N 2 -n 2 --requires="hosts:${i},${j}" -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/pt2pt/osu_latency |& tee ./results/osu/pairs/osu-latency-$i-$j.out
    flux run --exclusive -N 2 -n 2 --requires="hosts:${i},${j}" -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/pt2pt/osu_bw |& tee ./results/osu/pairs/osu-bw-$i-$j.out
    iter=$((iter+1))
  done
done
```

I also went back and did work while the usernetes cluster pods were up (also for OSU):

```bash
cd /usr/workspace/usernetes/experiments/osu
mkdir -p ./results/osu-with-usernetes/4
mkdir -p ./results/osu-with-usernetes/8
mkdir -p ./results/osu-with-usernetes/16
mkdir -p ./results/osu-with-usernetes/32
for iter in $(seq 1 10)
    do
    flux run -N4 -n 192 -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/collective/osu_allreduce |& tee ./results/osu-with-usernetes/4/osu-allreduce-$iter.out
    flux run -N8 -n 384 -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/collective/osu_allreduce |& tee ./results/osu-with-usernetes/8/osu-allreduce-$iter.out
    flux run -N16 -n 768 -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/collective/osu_allreduce |& tee ./results/osu-with-usernetes/16/osu-allreduce-$iter.out
    flux run -N32 -n 1536 -o cpu-affinity=per-task /usr/workspace/usernetes/osu/osu-benchmarks/build.openmpi/mpi/collective/osu_allreduce |& tee ./results/osu-with-usernetes/32/osu-allreduce-$iter.out
done
```

### Usernetes

Create the setup above first.

Install the flux operator.

```bash
kubectl apply -f https://raw.githubusercontent.com/flux-framework/flux-operator/refs/heads/main/examples/dist/flux-operator.yaml
kubectl apply -f crd/osu.yaml
```

#### LAMMPS

```bash
kubectl apply -f crd/lammps-openmpi.yaml
flux proxy local:///mnt/flux/view/run/flux/local bash
# These were not used
# export OMPI_MCA_opal_common_ucx_opal_mem_hooks=1
# export OMPI_MCA_btl_openib_allow_ib=true

export OMPI_MCA_opal_warn_on_missing_libcuda=0
export OMPI_MCA_btl=^openib,tcp,self,vader
export OMPI_MCA_btl=^openib,self,vader
export OMPI_MCA_pml=ucx
export OMPI_MCA_osc=ucx
export UCX_NET_DEVICES=mlx5_0:1
export UCX_TLS=rc,sm,self
# flux run  -N2 -n96 --requires="host:flux-sample-2,flux-sample-3" lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite

# ucp_context.c:1234 UCX  WARN  transport 'dc_ml5x' is not available, please use one or more of: cma, dc, dc_mlx5, dc_x, ib, mm, posix, rc, rc_mlx5, rc_v, rc_verbs, rc_x, self, shm, sm, sysv, tcp, ud, ud_mlx5, ud_v, ud_verbs, ud_x
# With CPU affinity - 40 seconds
flux run -N2 -n96 -o cpu-affinity=per-task lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite

# Without CPU affinity -- 47 seconds
flux run -N2 -n96 lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite

# cyclic distribution -- 46 seconds
flux run -N2 -n96 --taskmap=cyclic:2  lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite

# Only hit one numa node?
flux run -N2 -n48 --taskmap=cyclic:2  lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite

mkdir -p ./results/lammps/4
mkdir -p ./results/lammps/8
mkdir -p ./results/lammps/16
mkdir -p ./results/lammps/32
for iter in $(seq 1 10)
    do
    flux run -N4 -n192 -o cpu-affinity=per-task lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/4/lammps-$iter.out
#    flux run -N8 -n 384 -o cpu-affinity=per-task lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/8/lammps-$iter.out
    flux run -opmi=pmi2 -N16 -n 768 -o cpu-affinity=per-task lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/16/lammps-$iter.out
#    flux run -N32 -n 1536 -o cpu-affinity=per-task lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/32/lammps-$iter.out
done    
```

```bash
flux run -N2 -n48 --exclusive bash -c '
# Half the tasks per node because only using numa near infiniband device
TASKS_PER_NODE=24
TARGET_NUMA=1

# --- Coordination Logic (trying to avoid race..) ---
my_local_rank=$(($FLUX_TASK_RANK % TASKS_PER_NODE))
CPUSET_FILE_FINAL="/tmp/cpusets_for_node_$HOSTNAME"
CPUSET_FILE_TMP="${CPUSET_FILE_FINAL}.tmp"
if (( my_local_rank == 0 )); then
  numa_mask=$(hwloc-calc --physical numa:${TARGET_NUMA})
  local_cpusets=$(hwloc-distrib --restrict "$numa_mask" --taskset --single $TASKS_PER_NODE)
  echo "$local_cpusets" > "$CPUSET_FILE_TMP"
  mv "$CPUSET_FILE_TMP" "$CPUSET_FILE_FINAL"
fi
while [[ ! -f "$CPUSET_FILE_FINAL" ]]; do sleep 0.01; done

# Execution Logic ---
mapfile -t cpusets < "$CPUSET_FILE_FINAL"
my_cpuset=${cpusets[$my_local_rank]}

# Self-Binding and Launch (with clean output) ---
taskset_mask=${my_cpuset#0x}

# Bind this shell process, redirecting the noisy output to /dev/null.
taskset -p "$taskset_mask" $$ > /dev/null

echo "Global Rank $FLUX_TASK_RANK on $HOSTNAME is bound to mask $taskset_mask."

# Execute LAMMPS. It will inherit the correct affinity.
exec lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite
#exec /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite
'
```

- Bind only to numa 0 (not near infiniband device): 2:34
- Bind only to numa 1 (near infiniband device): 0:53
- No binding preferences with --exclusive: 1:58 
- No binding preferences without --exclusive: 1:57
- Using --cpu-affinity=per-task without exclusive. 0:51
- Same, but give more procs (-n48 to -n96 to use entire node): 1:18


This run:

```bash
flux run -N1 -n48 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite
```

Running lammps on on node in usernetes is 38 seconds. On bare metal is slower, 53 seconds.

Trying with SYS_NICE. We need this script:

```
#!/bin/bash
#
# elevate_priority.sh: A simple wrapper to elevate the scheduling priority
# of a command without changing its CPU affinity.

# --- Configuration ---
# Set the real-time priority. 1 is lowest, 99 is highest.
# A mid-range value like 50 is usually safe and effective.
RT_PRIORITY=50

# --- The Core Logic ---

# Use `chrt` to change the scheduling policy for THIS shell process.
# `$$` is a special variable for the current Process ID.
# -r : Set SCHED_RR (real-time round-robin) policy.
# -p : Operate on an existing PID.
# We redirect output to /dev/null to keep the job log clean.
chrt -r -p $RT_PRIORITY $$ > /dev/null 2>&1

# `exec` replaces this script process with the new program.
# The new program inherits the real-time scheduling priority we just set.
# `"$@"` passes all arguments (lmp, -v, -in, etc.) correctly.
exec "$@"
```
Then:
```
flux run -N2 -n96 -o cpu-affinity=per-task bash ./elevate_priority.sh lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite
```

Perf is a good idea, but need a way to get all PIDS for lammps.

```
perf stat -p "$PIDS"   -e cycles:u,cycles:k   -e instructions:u,instructions:k   --interval-print 2000
```
An example of how to put envars into a one-off run:

```
flux run -N2 -n96 --exclusive bash -c '
# This entire script runs on all 96 tasks.

# --- Configuration ---
LMP_PATH="/usr/workspace/usernetes/lammps/build/install/bin/lmp"
IMAGE_PATH="usernetes-python_lammps-flux-infiniband-openmpi-ucx-ubuntu2404.sif"
TASKS_PER_NODE=48

# --- Step 1: Leader Task on each Node Generates Cgroup Files ---

# Manually calculate the rank on this specific node (0-47).
my_local_rank=$(($FLUX_TASK_RANK % TASKS_PER_NODE))

# The "leader" task (local rank 0) does all the setup work for its node.
if (( my_local_rank == 0 )); then
  # Create a unique directory for this node''s cgroup files.
  cgroup_dir="/tmp/cgroups_${HOSTNAME}"
  mkdir -p "$cgroup_dir"

  # Get the list of all physical cores on the node. We will assign one task per core.
  # We use `hwloc-calc` to get a comma-separated list of core IDs.
  core_list=$(hwloc-calc --po --largest --no-smt -I core machine:0 | tr "\n" " ")

  # Create a cgroup file for each of the 48 tasks on this node.
  i=0
  for core_id in $core_list; do
    # Get the cpuset mask for this specific core.
    # `--taskset` gives us the clean hex mask format.
    cpuset_mask=$(hwloc-calc --taskset "core:$core_id")

    # This is the TOML format that Singularity''s --apply-cgroups expects.
    # We are setting the "cpus" field in the "cpu" controller.
    cat > "${cgroup_dir}/task_${i}.toml" <<EOF
[cpu]
cpus = "$cpuset_mask"
EOF
    # Increment the task counter.
    ((i++))
    # Break the loop once we''ve created files for all tasks on this node.
    if (( i >= TASKS_PER_NODE )); then
      break
    fi
  done
fi

# --- Step 2: All Tasks Wait for Their File and Launch Singularity ---

# All tasks wait for their specific cgroup file to be created by the leader.
my_cgroup_file="/tmp/cgroups_${HOSTNAME}/task_${my_local_rank}.toml"
while [[ ! -f "$my_cgroup_file" ]]; do
  sleep 0.01
done

# Now, launch singularity with the --apply-cgroups flag.
# Each task points to its own unique configuration file.
singularity exec \
  --apply-cgroups "$my_cgroup_file" \
  "$IMAGE_PATH" \
  /path/in/container/to/report_and_run.sh \
  "$LMP_PATH" -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite

# --- Step 3: Leader Task Cleans Up ---
# A barrier ensures all tasks are done with the files before cleanup.
# Note: Since `flux barrier` does not exist, we use a simple sleep.
# A more robust solution would use file-based signals for synchronization.
sleep 5
if (( my_local_rank == 0 )); then
  rm -rf "/tmp/cgroups_${HOSTNAME}"
fi
'
```
```

# ========== STEP 2: Configure and Launch the Main Job ==========

echo "Configuring job parameters..."

# --- Configuration: Define paths and arguments on the HOST system ---
AFFINITY_SCRIPT_PATH="$(pwd)/report_and_run.sh"
LMP_HOST_DIR="/usr/workspace/usernetes/lammps/build/install/bin"
IMAGE_PATH="usernetes-python_lammps-flux-infiniband-openmpi-ucx-ubuntu2404.sif"
LAMMPS_ARGS="-v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite"
LOG_FILE="singularity_affinity_run.log"

# --- The Flux Job Submission Command ---
echo "Starting LAMMPS run inside Singularity with custom affinity..."
echo "Log file will be: $LOG_FILE"

flux run -N2 -n96 --exclusive \
  singularity exec \
    --bind "$AFFINITY_SCRIPT_PATH:/usr/local/bin/report_and_run.sh" \
    --bind "$(pwd):/workdir" --pwd /workdir \
    "$IMAGE_PATH" \
    /usr/local/bin/report_and_run.sh \
    lmp \
    $LAMMPS_ARGS \
    2> "$LOG_FILE"

echo "Job finished. Affinity log has been written to $LOG_FILE"
```

For usernetes, we need report and run:

```
#!/bin/bash
#
# report_and_run.sh (v8): The final, definitive version.
# This script combines all previous fixes and uses a robust, flexible
# case statement to correctly handle zero-padded hex values.

# 1. Get basic info.
rank="$FLUX_TASK_RANK"
node=$(hostname)
binding=$(hwloc-bind --get)

# 2. Analyze the binding.
core_list=$(hwloc-calc --pulist "$binding")
first_core=$(echo "$core_list" | cut -d, -f1)

# --- This part is now correct and tested ---
# Use a precise grep to get only the correct "nodeset" line.
nodeset_line=$(hwloc-info "pu:$first_core" | grep "^ *nodeset =")
# Extract the hex value and aggressively clean any whitespace.
nodeset_hex=$(echo "$nodeset_line" | awk '{print $3}' | tr -d '[:space:]')


# --- THE FINAL FIX IS HERE ---
# Use a flexible case statement that checks what the string ENDS WITH.
# This correctly handles both "0x1" and "0x00000001".
numa_domain="unknown"
case "$nodeset_hex" in
  *1) numa_domain="0" ;;
  *2) numa_domain="1" ;;
  *4) numa_domain="2" ;;
  *8) numa_domain="3" ;;
  *)  numa_domain="err_final_case_fail" ;;
esac

# 3. Print all captured information to standard error.
echo "$rank $node $binding $numa_domain" >&2


# 2. Execute the real application.
# `exec` replaces the script with lmp, which is efficient.
exec lmp "$@"
```

```
# ========== STEP 2: Configure and Launch the Main Job ==========

flux run -N2 -n96 --exclusive /bin/bash ./report_and_run.sh lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite

echo "Job finished. Affinity log has been written to $LOG_FILE"
```

```bash
flux run -N2 --env UCX_TLS=rc_x,sm,self --env OMPI_MCA_pml=ucx --env UCX_NET_DEVICES=mlx5_0:1
```

#### OSU

To get hosts, I started with the list from bare metal:

```bash
'corona192',
 'corona198',
 'corona202',
 'corona206',
 'corona226',
 'corona228',
 'corona229',
 'corona232'}
```

And mapped them to physical nodes:

```
hosts="flux-sample-11 flux-sample-1 flux-sample-26 flux-sample-22 flux-sample-29 flux-sample-8 flux-sample-14 flux-sample-17"
```

```
flux-sample-0-6798k    1/1     Running   0          6m58s   10.244.22.3   u7s-corona223   <none>           <none>
flux-sample-1-kk6b5    1/1     Running   0          6m58s   10.244.11.2   u7s-corona202   <none>           <none>
flux-sample-10-pqn28   1/1     Running   0          6m58s   10.244.0.2    u7s-corona188   <none>           <none>
flux-sample-11-hd7ln   1/1     Running   0          6m58s   10.244.7.2    u7s-corona198   <none>           <none>
flux-sample-12-zkfrx   1/1     Running   0          6m58s   10.244.14.2   u7s-corona205   <none>           <none>
flux-sample-13-tv5gz   1/1     Running   0          6m58s   10.244.5.2    u7s-corona197   <none>           <none>
flux-sample-14-lnpfj   1/1     Running   0          6m58s   10.244.29.2   u7s-corona232   <none>           <none>
flux-sample-15-wgzw2   1/1     Running   0          6m58s   10.244.28.2   u7s-corona230   <none>           <none>
flux-sample-16-x4sv9   1/1     Running   0          6m58s   10.244.6.2    u7s-corona196   <none>           <none>
flux-sample-17-jd5tp   1/1     Running   0          6m58s   10.244.27.2   u7s-corona228   <none>           <none>
flux-sample-18-tdpdx   1/1     Running   0          6m58s   10.244.16.2   u7s-corona207   <none>           <none>
flux-sample-19-c786s   1/1     Running   0          6m58s   10.244.13.2   u7s-corona204   <none>           <none>
flux-sample-2-p7fp8    1/1     Running   0          6m58s   10.244.10.2   u7s-corona201   <none>           <none>
flux-sample-20-4r9bc   1/1     Running   0          6m58s   10.244.24.2   u7s-corona225   <none>           <none>
flux-sample-21-p4ztb   1/1     Running   0          6m58s   10.244.17.2   u7s-corona213   <none>           <none>
flux-sample-22-xc8ct   1/1     Running   0          6m58s   10.244.15.2   u7s-corona206   <none>           <none>
flux-sample-23-w8dgr   1/1     Running   0          6m58s   10.244.12.2   u7s-corona203   <none>           <none>
flux-sample-24-qsz2n   1/1     Running   0          6m58s   10.244.19.2   u7s-corona219   <none>           <none>
flux-sample-25-4zv8g   1/1     Running   0          6m58s   10.244.1.2    u7s-corona189   <none>           <none>
flux-sample-26-w7hk6   1/1     Running   0          6m58s   10.244.2.2    u7s-corona192   <none>           <none>
flux-sample-27-qdjnh   1/1     Running   0          6m58s   10.244.26.2   u7s-corona227   <none>           <none>
flux-sample-28-492z2   1/1     Running   0          6m58s   10.244.30.2   u7s-corona233   <none>           <none>
flux-sample-29-lgn4d   1/1     Running   0          6m58s   10.244.25.2   u7s-corona226   <none>           <none>
flux-sample-3-wl2c4    1/1     Running   0          6m58s   10.244.4.2    u7s-corona194   <none>           <none>
flux-sample-30-mgqmp   1/1     Running   0          6m58s   10.244.9.2    u7s-corona200   <none>           <none>
flux-sample-31-2hnvs   1/1     Running   0          6m58s   10.244.3.2    u7s-corona193   <none>           <none>
flux-sample-4-9vv77    1/1     Running   0          6m58s   10.244.21.2   u7s-corona222   <none>           <none>
flux-sample-5-xnxqg    1/1     Running   0          6m58s   10.244.23.2   u7s-corona224   <none>           <none>
flux-sample-6-g87cl    1/1     Running   0          6m58s   10.244.20.2   u7s-corona221   <none>           <none>
flux-sample-7-hjjgz    1/1     Running   0          6m58s   10.244.18.2   u7s-corona214   <none>           <none>
flux-sample-8-4zl2x    1/1     Running   0          6m58s   10.244.31.4   u7s-corona229   <none>           <none>
flux-sample-9-rsjj4    1/1     Running   0          6m58s   10.244.8.2    u7s-corona199   <none>           <none>

```

```bash
. /mnt/flux/flux-view.sh 
flux proxy $fluxsocket bash
mkdir -p ./results/osu/pairs
mkdir -p ./results/osu/4
mkdir -p ./results/osu/8
mkdir -p ./results/osu/16
mkdir -p ./results/osu/32

hosts="flux-sample-11 flux-sample-1 flux-sample-26 flux-sample-22 flux-sample-29 flux-sample-8 flux-sample-14 flux-sample-17"
list=${hosts}

dequeue_from_list() {
  shift;
  list=$@
}

iter=0
for i in $hosts; do
  dequeue_from_list $list
  for j in $list; do
    echo "${i} ${j}"
    flux run --exclusive -N 2 -n 2 --requires="hosts:${i},${j}" -o cpu-affinity=per-task osu_latency |& tee ./results/osu/pairs/osu-latency-$i-$j.out
    flux run --exclusive -N 2 -n 2 --requires="hosts:${i},${j}" -o cpu-affinity=per-task osu_bw |& tee ./results/osu/pairs/osu-bw-$i-$j.out
    iter=$((iter+1))
  done
done

export OMPI_MCA_opal_warn_on_missing_libcuda=0
export OMPI_MCA_pml=ucx
export OMPI_MCA_osc=ucx
export UCX_NET_DEVICES=mlx5_0:1
export UCX_TLS=rc,sm,self
for iter in $(seq 1 10)
  do
    flux run -N4 -n 192 -o cpu-affinity=per-task osu_allreduce |& tee ./results/osu/4/osu-allreduce-$iter.out
    flux run -N8 -n 384 -o cpu-affinity=per-task osu_allreduce |& tee ./results/osu/8/osu-allreduce-$iter.out
    flux run -N16 -n 768 -o cpu-affinity=per-task osu_allreduce |& tee ./results/osu/16/osu-allreduce-$iter.out
    flux run -N32 -n 1536 -o cpu-affinity=per-task osu_allreduce |& tee ./results/osu/32/osu-allreduce-$iter.out
done
```

#### AMG


```bash
flux proxy local:///mnt/flux/view/run/flux/local bash

export OMPI_MCA_opal_warn_on_missing_libcuda=0
export OMPI_MCA_pml=ucx
export OMPI_MCA_osc=ucx
export UCX_NET_DEVICES=mlx5_0:1
export UCX_TLS=rc,sm,self

# Note that I tested 4 6 4 and it exited the pod.
mkdir -p ./results
for iter in $(seq 1 9)
  do
    flux run -N2 -n 96 -o cpu-affinity=per-task amg -n 256 256 128 -P 4 4 6 -problem 2 |& tee ./results/amg2023-$iter.out
    echo "FLUX EVENTS" >> ./results/amg2023-$iter.out
    flux job info $(flux job last) eventlog >> ./results/amg2023-$iter.out
    echo "FLUX RESOURCES" >> ./results/amg2023-$iter.out
    flux job info $(flux job last) R >> ./results/amg2023-$iter.out
done
```


# LAMMPS Bare Metal

(with Usernetes + pods idle, plus with usernetes and no pods)

#### LAMMPS


```bash
cd /usr/workspace/usernetes/experiments/lammps
export LD_LIBRARY_PATH=/usr/workspace/usernetes/lammps/build/install/lib64
mkdir -p ./results/lammps-with-usernetes/4
mkdir -p ./results/lammps-with-usernetes/8
mkdir -p ./results/lammps-with-usernetes/16
mkdir -p ./results/lammps-with-usernetes/32
for iter in $(seq 1 10)
    do
    flux run -N4 -n 192 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-with-usernetes/4/lammps-$iter.out
    flux run -N8 -n 384 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-with-usernetes/8/lammps-$iter.out
    flux run -N16 -n 768 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-with-usernetes/16/lammps-$iter.out
    flux run -N32 -n 1536 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-with-usernetes/32/lammps-$iter.out
done

# Then delete the lammps pods...
cd /usr/workspace/usernetes/experiments/lammps
export LD_LIBRARY_PATH=/usr/workspace/usernetes/lammps/build/install/lib64
mkdir -p ./results/lammps-usernetes-pods/4
mkdir -p ./results/lammps-usernetes-pods/8
mkdir -p ./results/lammps-usernetes-pods/16
mkdir -p ./results/lammps-usernetes-pods/32
for iter in $(seq 1 10)
    do
    flux run -N4 -n 192 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-usernetes-pods/4/lammps-$iter.out
    flux run -N8 -n 384 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-usernetes-pods/8/lammps-$iter.out
    flux run -N16 -n 768 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-usernetes-pods/16/lammps-$iter.out
    flux run -N32 -n 1536 -o cpu-affinity=per-task /usr/workspace/usernetes/lammps/build/install/bin/lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps-usernetes-pods/32/lammps-$iter.out
done
```
