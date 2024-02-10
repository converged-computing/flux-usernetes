# Mninst with Pytorch 

Since MPI doesn't work on a standard instance network, we are going to try for mnist instead for the following cases:

1. mnist with flux on bare metal vs.
2. mnist with flux via the flux operator
3. mnist with single node for cases 1 and 2 (to show if networking is the issue)

## 1. Mnist with Flux on Bare Metal

Each run is 1 epoch, batch size 48 on world size 48 (6 nodes x 8 processes each) for a mini batch size of 1. It takes about 10 minutes, 20 seconds.

Download the container and ensure it's on all nodes.

```bash
mkdir -p ~/mnist
cd ~/mnist

singularity pull docker://kubeflowkatib/pytorch-mnist-cpu:latest 
wget https://raw.githubusercontent.com/converged-computing/flux-usernetes/main/aws/examples/mnist/scripts/main.py
wget https://raw.githubusercontent.com/converged-computing/flux-usernetes/main/aws/examples/mnist/scripts/launch.sh
wget https://raw.githubusercontent.com/converged-computing/flux-usernetes/main/aws/examples/mnist/scripts/mnist.sh
wget https://raw.githubusercontent.com/converged-computing/flux-usernetes/main/aws/examples/mnist/scripts/mnist-single-node.sh
```

And send the files to all nodes. **Important** don't forget to change the leader name in mnist.sh!

```bash
flux exec -x 0 -r all mkdir -p /home/ubuntu/mnist
flux exec -x 0 -r all singularity pull /home/ubuntu/mnist/pytorch-mnist-cpu_latest.sif docker://kubeflowkatib/pytorch-mnist-cpu:latest 
flux filemap map -C /home/ubuntu/mnist mnist.sh
flux filemap map -C /home/ubuntu/mnist mnist-single-node.sh
flux filemap map -C /home/ubuntu/mnist launch.sh
flux filemap map -C /home/ubuntu/mnist main.py
flux exec -x 0 -r all flux filemap get -C /home/ubuntu/mnist
flux exec -x 0 -r all chmod +x /home/ubuntu/mnist/*.sh
flux exec -x 0 -r all ls /home/ubuntu/mnist
```

We can run this in a loop, and save the final time for each.

```bash
mkdir -p ./results/bare-metal
for i in $(seq 1 20); do 
    echo "Running iteration ${i}"
    log=/home/ubuntu/mnist/results/bare-metal/${i}-mnist.out
    flux run -N 2 /home/ubuntu/mnist/mnist.sh |& tee ${log}
done
```

## 2. Mnist with Flux via the Flux Operator

Again, download the minicluster.yaml files

```bash
wget https://raw.githubusercontent.com/converged-computing/flux-usernetes/main/aws/examples/mnist/scripts/minicluster.yaml
wget https://raw.githubusercontent.com/converged-computing/flux-usernetes/main/aws/examples/mnist/scripts/minicluster-single-node.yaml
```
```bash
# We should already have this
cd ./mnist
mkdir -p ./results/usernetes

# Autocomplete
source <(kubectl completion bash) 

# Sanity check your cluster is there...
kubectl get nodes
```

```bash
# install the flux operator 
kubectl apply -f https://raw.githubusercontent.com/flux-framework/flux-operator/test-refactor-modular/examples/dist/flux-operator-refactor-arm.yaml

# Ensure it is working!
kubectl logs -n operator-system operator-controller-manager-75d9f46b7c-xltbl
```

Here is how we can run the experiments, first with a setup and test run:

```bash
# Run once to pull containers to nodes (this will be thrown away)
kubectl apply -f minicluster.yaml

# For two nodes (yes this is a bad idea to remove) YOLOOOO
kubectl taint nodes u7s-i-0f21fcfb779b72cd7 node-role.kubernetes.io/control-plane:NoSchedule-

# Test these commands before running in loop
pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)

# This will stream until it finishes
echo "Lead broker pod is ${pod}"
kubectl logs ${pod} -f

# And this absolutely waits until the job is deemed complete
kubectl wait --for=condition=complete job/flux-sample
kubectl delete -f minicluster.yaml --wait=true
```

And now let's automate the entire thing.

```bash
for i in $(seq 1 20); do 
    echo "Running iteration ${i}"
    kubectl apply -f minicluster.yaml
    sleep 10
    pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)
    echo "Lead broker pod is ${pod}"
    # Wait for init to finish and pod to initialize
    kubectl wait --for=condition=ready --timeout=120s pod/${pod}
    sleep 10
    kubectl get pods -o wide
    # This waits for mnist to finish (streaming the log)
    kubectl logs ${pod} -f |& tee ./results/usernetes/mnist-${i}.out
    # And an extra precaution the entire job/workers are complete
    kubectl wait --for=condition=complete --timeout=120s job/flux-sample
    kubectl delete -f minicluster.yaml --wait=true
done
```

## 3. Mnist with Single Node (Bare Metal Flux) and Usernetes

This case should give us a better sense if the networking (between nodes) is the underlying issue that shows usernetes a lot slower. This is a proxy for just measuring networking directly with performance metrics. You should have the same setup as defined in step 1. to start. Let's make different directory, and launch with a different number of nodes. Note that we are updating the script to handle just one node:
And now we can do a test run to get a time:

```bash
flux run -N 1 /home/ubuntu/mnist/mnist-single-node.sh

# And test saving to an output file

```bash
log=/tmp/test.out
flux submit -N 1 --out ${log} --err ${log} /home/ubuntu/mnist/mnist-single-node.sh
```

That seems to work! Let's run 20x, and we will save output across the nodes and find it later.

```bash
flux exec mkdir -p /home/ubuntu/mnist/results/bare-metal-single-node
for i in $(seq 1 20); do 
    echo "Running iteration ${i}"
    log=/home/ubuntu/mnist/results/bare-metal-single-node/mnist-${i}.out
    flux submit -N 1 --out ${log} --err ${log} /home/ubuntu/mnist/mnist-single-node.sh
done
```

This is a nicer strategy with submit because we can run N at a time!
Now for running in Kubernetes (you should still have the operator installed)

```bash
mkdir -p ./results/usernetes-single-node
```
Here is how we can run the experiments, first with a setup and test run:

```bash
# Run once to pull containers to nodes (this will be thrown away)
kubectl apply -f minicluster-single-node.yaml

# Test these commands before running in loop
pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)

# This will stream until it finishes
echo "Lead broker pod is ${pod}"
kubectl logs ${pod} -f

# And this absolutely waits until the job is deemed complete
kubectl wait --for=condition=complete job/flux-sample
kubectl delete -f minicluster-single-node.yaml --wait=true
```

And now let's automate the entire thing.

```bash
# use screen if it might cut
screen /bin/bash

mkdir -p ./results/usernetes-single-node
for i in $(seq 1 20); do 
    echo "Running iteration ${i}"
    kubectl apply -f minicluster-single-node.yaml
    sleep 10
    pod=$(kubectl get pods -o json | jq -r .items[0].metadata.name)
    echo "Lead broker pod is ${pod}"
    # Wait for init to finish and pod to initialize
    kubectl wait --for=condition=ready --timeout=120s pod/${pod}
    sleep 10
    kubectl get pods -o wide
    # This waits for mnist to finish (streaming the log)
    kubectl logs ${pod} -f |& tee ./results/usernetes-single-node/mnist-${i}.out
    # And an extra precaution the entire job/workers are complete
    kubectl wait --for=condition=complete --timeout=120s job/flux-sample
    kubectl delete -f minicluster-single-node.yaml --wait=true
done
```

When you are done, don't forget to scp all the data to your local machine.
And then we can do the data analysis locally (below) and delete the operator, clean up the VMs if you like.

## Analyze Data

Install dependencies. 

```bash
pip install -r ../requirements.txt

# These should be the defaults
python plot-flux-operator-vs-bare-metal.py
python plot-single-node.py
```

Results will be added, TBA.