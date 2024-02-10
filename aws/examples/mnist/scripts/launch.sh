#!/bin/bash

job_name="flux-sample"
job_port="8080"
container="/home/ubuntu/mnist/pytorch-mnist-cpu_latest.sif"

# Read all the hostname the job is running
nodenames=$(flux exec -r all hostname)
echo "Found nodes ${nodenames}"
# separate the names into an array
IFS=' '
read -ra node_names <<< ${nodenames}
leader=${node_names[0]}
echo "The leader broker is ${leader}"

# Get the number of nodes
nodes=$(echo $nodenames | wc -l)
echo "There are ${nodes} nodes in the cluster"

# Get the task rank
rank=0
for host in $(flux exec -r all hostname)
do
   if [[ "${host}" == "$(hostname)" ]]; then
       echo "This is ${host} with rank ${rank}"
       break
   fi
   ((rank++))
done

echo "I am hostname $(hostname) and rank ${rank} of ${nodes} nodes. The job is ${job_name} and master is on port ${job_port}"

# This will be parsed by the main.py to get the rank
export LOCAL_RANK=${rank}

time singularity exec ${container} torchrun --node_rank ${LOCAL_RANK} --nnodes ${nodes} --nproc_per_node 8 --master_addr ${leader} --master_port ${job_port} /home/ubuntu/mnist/main.py
