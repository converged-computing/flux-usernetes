# Corona Experiments

Still need to do:

- usernetes sizes 8,16,32 for osu
- usernetes all sizes for lammps

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
flux proxy local:///mnt/flux/view/run/flux/local bash
# These were not used
# export OMPI_MCA_opal_common_ucx_opal_mem_hooks=1
# export OMPI_MCA_btl_openib_allow_ib=true

export OMPI_MCA_opal_warn_on_missing_libcuda=0
export OMPI_MCA_btl=^openib,tcp,self,vader
export OMPI_MCA_pml=ucx
export OMPI_MCA_osc=ucx
export UCX_NET_DEVICES=mlx5_0:1
export UCX_TLS=rc,sm,self
# flux run  -N2 -n96 --requires="host:flux-sample-2,flux-sample-3" lmp -v x 8 -v y 8 -v z 8 -in in.reaxc.hns -nocite

mkdir -p ./results/lammps/4
mkdir -p ./results/lammps/8
mkdir -p ./results/lammps/16
mkdir -p ./results/lammps/32
for iter in $(seq 1 10)
    do
    flux run -N4 -n192 -o cpu-affinity=per-task lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/4/lammps-$iter.out
    flux run -N8 -n 384 -o cpu-affinity=per-task lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/8/lammps-$iter.out
    flux run -N16 -n 768 -o cpu-affinity=per-task lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/16/lammps-$iter.out
    flux run -N32 -n 1536 -o cpu-affinity=per-task lmp -v x 16 -v y 16 -v z 16 -in in.reaxc.hns -nocite |& tee ./results/lammps/32/lammps-$iter.out
done    
```

An example of how to put envars into a one-off run:

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
