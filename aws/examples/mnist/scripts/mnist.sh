#!/bin/bash

job_name="flux-sample"
job_port="8080"
container="/home/ubuntu/mnist/pytorch-mnist-cpu_latest.sif"

# Hard code the leader for now
leader=u2204-02
echo "The leader broker is ${leader}"
nodes=${FLUX_JOB_NNODES}
rank=${FLUX_TASK_RANK}
echo "I am hostname $(hostname) and rank ${rank} of ${nodes} nodes"
time singularity exec ${container} torchrun --node_rank ${rank} --nnodes ${nodes} --nproc_per_node 8 --master_addr ${leader} --master_port ${job_port} /home/ubuntu/mnist/main.py
