# GKE GPU Experiment Testing

> This is for early testing of a GPU workload.

## Experiment

### 1. Setup

Bring up the cluster (with some number of nodes) and install the drivers. Note that since there is no rule about pods mapping to nodes, it will be entirely determined by GPU devices (e.g., if you ask for one container to require 4 and there are 4/node, you get 1:1).

```bash
GOOGLE_PROJECT=llnl-flux
GPUS=4

# Configurations we are testing:
# This is a test to not provide "enough" CPU per GPU
NODES=1; INSTANCE=n1-standard-4

# This is what we are supposed to provide
NODES=1; INSTANCE=n1-standard-16

# This is testing 2 nodes
NODES=2; INSTANCE=n1-standard-16

# This is testing 4 nodes
NODES=4; INSTANCE=n1-standard-16

time gcloud container clusters create gpu-cluster-4 \
    --threads-per-core=1 \
    --accelerator type=nvidia-tesla-v100,count=$GPUS,gpu-driver-version=latest \
    --num-nodes=$NODES \
    --machine-type=$INSTANCE \
    --enable-gvnic \
    --network=mtu9k \
    --system-config-from-file=./system-config.yaml \
    --region=us-central1-a \
    --project=${GOOGLE_PROJECT} 
```

Sanity check installed on all nodes

```bash
kubectl get nodes -o json | jq .items[].status.allocatable
kubectl get nodes -o json | jq .items[].status.allocatable | grep nvidia | wc -l
```
```
4
```

Install the PytorchJob (Kubeflow) operator:

```bash
# Install version 1 of the pytorch training-operator
kubectl apply --server-side -k "github.com/kubeflow/training-operator.git/manifests/overlays/standalone?ref=v1.8.1"
# Webhooks take a hot minute ;)
sleep 20
```

Next I had downloaded a [starting workflow](kubectl create -f https://raw.githubusercontent.com/kubeflow/training-operator/refs/heads/release-1.9/examples/pytorch/simple.yaml) and customized it to add a time wrapper, GPUs, and remove a custom namespace. I did a variant without GPU (not shown here). Note that since this isn't a final experiment, I changed it as I went.

```bash
# Takes only about 30 seconds to pull.
kubectl apply -f ./simple.yaml
kubectl logs pytorch-mnist-master-0 -f
```
```console
$ kubectl get pods
NAME                     READY   STATUS              RESTARTS   AGE
pytorch-mnist-master-0   0/1     ContainerCreating   0          3s
pytorch-mnist-worker-0   0/1     Init:0/1            0          2s
pytorch-mnist-worker-1   0/1     Init:0/1            0          2s
pytorch-mnist-worker-2   0/1     Init:0/1            0          2s
```

## Application

Here are all the entrypoint customizations:

```console
usage: mnist.py [-h] [--batch-size N] [--test-batch-size N] [--epochs N]
                [--lr LR] [--momentum M] [--no-cuda] [--seed S]
                [--log-interval N] [--log-path LOG_PATH] [--save-model]
                [--backend {gloo,nccl,mpi}]

PyTorch MNIST Example

optional arguments:
  -h, --help            show this help message and exit
  --batch-size N        input batch size for training (default: 64)
  --test-batch-size N   input batch size for testing (default: 1000)
  --epochs N            number of epochs to train (default: 10)
  --lr LR               learning rate (default: 0.01)
  --momentum M          SGD momentum (default: 0.5)
  --no-cuda             disables CUDA training
  --seed S              random seed (default: 1)
  --log-interval N      how many batches to wait before logging training
                        status
  --log-path LOG_PATH   Path to save logs. Print to StdOut if log-path is not
                        set
  --save-model          For Saving the current Model
  --backend {gloo,nccl,mpi}
                        Distributed backend
```
I wound up adding the backend to be nccl, and I'm thinking it would have done that anyway detecting the GPU.
Note that we can use gloo, nccl, or mpi. Since we are testing GPU, we should use nccl!

## Results

All result logs are in [logs](logs).

### CPU

I only did one CPU run, just for a quick comparison.

- 1 node, 1 epoch, worker and master using CPU gloo backend (this is n1-standard-4, so tiny)
  - time: 4m 27s
  - accuracy: 0.7330
  - loss: 0.6635

### GPU

#### 1 node, 2 GPU/worker, n1-standard-4

> This is a test to see what happens if the GPU is lacking CPU resources

For quick testing, all of these use nccl now and 2 GPU devices for each of master and worker.

- 1 node, 1 epoch, worker and master each with 2 GPU devices
  - time: 2m33.741s
  - accuracy: 0.7317
  - loss: 0.6655  

- 1 node, 2 epoch, worker and master each with 2 GPU devices
  - time: 4m54.787s
  - accuracy: 0.7685
  - loss:   0.5843

#### 1 node, 2 GPU/worker, n1-standard-16

> This is the minimum number of CPU we should provide.

- 1 node, 1 epoch, worker and master each with 2 GPU devices
  - time: 38.602s
  - accuracy: 0.7322
  - loss: 0.6646

That is so much faster! After that I moved up to 8 epochs.

- 1 node, 8 epoch, worker and master each with 2 GPU devices
  - time: 1m5.67 seconds
  - accuracy: 0.7322
  - loss: 0.6646

No idea why it only doubled in time. Maybe I missed something (see the logs). I decided to increase the batch size from the default of 64 up to 128:

- 1 node, 8 epoch, worker and master each with 2 GPU devices, batch size 128
  - time: 0m57.146s
  - accuracy: 0.8470
  - loss: 0.4273

I didn't save the node json for this one, the difference would be n1-standard-4 vs n1-standard-16.

#### 2 node, 4 GPU/worker

This would be a mapping of an entire node to one worker, which is the most straight forward design I think.

- 2 node, 8 epoch, worker and master each with 4 GPU devices, batch size 128
  - time: 1m36.533s
  - accuracy: 0.8473
  - loss: 0.4280

- 2 node, 10 epoch, worker and master each with 4 GPU devices, batch size 128
  - time: 1m20.745s
  - accuracy: 0.8638
  - loss: 0.3840

- 2 node, 20 epoch, worker and master each with 4 GPU devices, batch size 128
  - time: 2m20.677s
  - accuracy: 0.8849
  - loss: 0.3264


#### 4 node, 4 GPU/worker

Subjectively speaking, the "hookup" time (at the start after download before we see epochs running) seems to take longer.

- 4 node, 8 epoch, workers and master each with 4 GPU devices, batch size 128
  - time: 1m42.795s
  - accuracy: 0.8502
  - loss: 0.4259

- 4 node, 10 epoch, workers and master each with 4 GPU devices, batch size 128
  - time: 1m27.389s
  - accuracy: 0.8635
  - loss: 0.3842

- 4 node, 20 epoch, workers and master each with 4 GPU devices, batch size 128
  - time: 2m32.848s 
  - accuracy: 0.8850
  - loss: 0.3262

## Notes

- Our largest cluster size will likely be more limited by capacity than anything else.
- If we go up to size 32 cluster (nodes) of 4 GPU per node, that is about $12/node/hour
  - size 32 would be $384/hour, ideally we wouldn't have it up an hour
  - size 16 would be $192/hour
  - size 8 == $96/hour
  - size 4 == $48/hour
  
Whatever we decide, we will want to automate this completely (likely will helm).

## Cleanup 

```bash
gcloud container clusters delete gpu-cluster-4 --region us-central1-a
```

## Questions

- Do we still want one thread per core?
- What batch size / epochs do we want?
- Does 4 GPU/node make sense? (it would be ~12/hour, rounded up, per node)
- We need to choose epochs / batch size that makes sense for our cost estimates.
- I think we should keep doubling in size until we can't get resources. I suspect it will happen quickly.
