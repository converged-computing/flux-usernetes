#!/bin/bash

# This is a single node run, for use in the flux operator

# Hard code the leader for now
leader=$(hostname)
nodes=${FLUX_JOB_NNODES}
rank=${FLUX_TASK_RANK}
echo "I am hostname $(hostname) and rank ${rank} of ${nodes} nodes"

time python3 /main.py --epochs 5
