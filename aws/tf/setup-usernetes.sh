#!/bin/bash

# This is a more "on the fly" install script for usernetes.
# if we try to tweak the clone in the VM we can get permission or mismatch
# in version issues.
rm -rf /home/ubuntu/usernetes
git clone https://github.com/rootless-containers/usernetes ~/usernetes
cd ~/usernetes
echo "Usernetes is in ~/usernetes"

cat <<EOF | tee ./start-control-plane.sh
#!/bin/bash

# Go to usernetes home
cd ~/usernetes

# This is logic for the lead broker (we assume this one)
make up

sleep 10
make kubeadm-init
sleep 5
make install-flannel
make kubeconfig
export KUBECONFIG=/home/ubuntu/usernetes/kubeconfig
make join-command
echo "export KUBECONFIG=/home/ubuntu/usernetes/kubeconfig" >> ~/.bashrc
EOF
chmod +x ./start-control-plane.sh

cat <<EOF | tee ./start-worker.sh
#!/bin/bash

# Go to usernetes home
cd ~/usernetes

make up
sleep 5

# This assumes join-command is already here
make kubeadm-join
EOF
chmod +x ./start-worker.sh

# Update usernetes with config with higher MTU
rm -rf docker-compose.yaml
wget https://raw.githubusercontent.com/converged-computing/flux-usernetes/experiment-end-june/aws/tf/docker-compose.yaml
wget https://raw.githubusercontent.com/converged-computing/flux-usernetes/experiment-end-june/aws/tf/Makefile.usernetes
mv Makefile.usernetes Makefile
