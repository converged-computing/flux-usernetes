#!/bin/bash

# We are hardcoding these for now, would be better to use envars
# Get the number of nodes (I think JOB_COMPLETIONS would work here)
job_port="8080"
nodes=${1:-6}

# This is the job name, index, service name, and namespace (default)
leader="flux-sample-0.flux-service.default.svc.cluster.local"

# Cheat to get the rank - last bit of hostname
# The job index variable doesn't seem to work here, I think it needs to be exported
name=$(hostname)
IFS='-' read -ra ADDR <<< "${name}"
for i in "${ADDR[@]}"; do
  rank=${i}
done

echo "The leader broker is ${leader}"
echo "I am hostname $(hostname) and rank ${rank} of ${nodes} nodes"

time torchrun --node_rank ${rank} --nnodes ${nodes} --nproc_per_node 8 --master_addr ${leader} --master_port ${job_port} /main.py
