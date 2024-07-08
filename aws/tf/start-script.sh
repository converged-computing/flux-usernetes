#!/bin/bash

# Install AWS client
python3 -m pip install awscli

# Wait for the count to be up
while [[ $(aws ec2 describe-instances --region us-east-1 --filters "Name=tag:selector,Values=${selector_name}-selector" | jq .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateDnsName | wc -l) -ne ${desired_size} ]]
do
   echo "Desired count not reached, sleeping."
   sleep 10
done
found_count=$(aws ec2 describe-instances --region us-east-1 --filters "Name=tag:selector,Values=${selector_name}-selector" | jq .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddress | wc -l)
echo "Desired count $found_count is reached"

# Update the flux config files with our hosts - we need the ones from hostname
hosts=$(aws ec2 describe-instances --region us-east-1 --filters "Name=tag:selector,Values=${selector_name}-selector" | jq -r .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateDnsName)

# Hack them together into comma separated list, also get the lead broker
NODELIST=""
lead_broker=""
for host in $hosts; do
   barehost=$(python3 -c "print('$host'.split('.')[0])")
   if [[ "$NODELIST" == "" ]]; then
      NODELIST=$barehost
      lead_broker=$barehost
   else
      NODELIST=$NODELIST,$barehost
   fi
done

# Generate the flux resource file
# This is just in case it exists
sudo rm -rf /etc/flux/system/R
flux R encode --hosts=$NODELIST --local > R
sudo mv R /etc/flux/system/R
sudo chown ubuntu /etc/flux/system/R

# Figure out the lead broker, the first in the list
echo "The lead broker is $lead_broker"
host=$(hostname)
echo "The host is $host"

# Make the run directories in case not made yet
sudo mkdir -p /run/flux
mkdir -p /home/ubuntu/run/flux
sudo chown -R ubuntu /run/flux

# Write updated broker.toml
cat <<EOF | tee /tmp/broker.toml
# Flux needs to know the path to the IMP executable
[exec]
imp = "/usr/libexec/flux/flux-imp"

# Allow users other than the instance owner (guests) to connect to Flux
# Optionally, root may be given "owner privileges" for convenience
[access]
allow-guest-user = true
allow-root-owner = true

# Point to resource definition generated with flux-R(1).
# Uncomment to exclude nodes (e.g. mgmt, login), from eligibility to run jobs.
[resource]
path = "/etc/flux/system/R"

# Point to shared network certificate generated flux-keygen(1).
# Define the network endpoints for Flux's tree based overlay network
# and inform Flux of the hostnames that will start flux-broker(1).
[bootstrap]
curve_cert = "/etc/flux/system/curve.cert"

# ubuntu does not have eth0
default_port = 8050
default_bind = "tcp://${ethernet_device}:%p"
default_connect = "tcp://%h.ec2.internal:%p"

# Rank 0 is the TBON parent of all brokers unless explicitly set with
# parent directives.
# The actual ip addresses (for both) need to be added to /etc/hosts
# of each VM for now.
hosts = [
   { host = NODELIST },
]
# Speed up detection of crashed network peers (system default is around 20m)
[tbon]
tcp_user_timeout = "2m"
EOF

sudo mkdir -p /etc/flux/system/conf.d

# Replace in hostlist
sed -i 's/NODELIST/"'"$NODELIST"'"/g' /tmp/broker.toml
sudo mv /tmp/broker.toml /etc/flux/system/conf.d/broker.toml

# Write new service file
cat <<EOF | tee /tmp/flux.service
[Unit]
Description=Flux message broker
Wants=munge.service

[Service]
Type=notify
NotifyAccess=main
TimeoutStopSec=90
KillMode=mixed
ExecStart=/bin/bash -c '\
  XDG_RUNTIME_DIR=/run/user/$UID \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus \
  /usr/bin/flux broker \
  --config-path=/etc/flux/system/conf.d \
  -Scron.directory=/etc/flux/system/cron.d \
  -Srundir=/home/ubuntu/run/flux \
  -Sstatedir=/var/lib/flux \
  -Slocal-uri=local:///home/ubuntu/run/flux/local \
  -Slog-stderr-level=6 \
  -Slog-stderr-mode=local \
  -Sbroker.rc2_none \
  -Sbroker.quorum=1 \
  -Sbroker.quorum-timeout=none \
  -Sbroker.exit-norestart=42 \
  -Sbroker.sd-notify=1 \
  -Scontent.restore=auto'
SyslogIdentifier=flux
ExecReload=/usr/bin/flux config reload
LimitMEMLOCK=infinity
Restart=always
RestartSec=5s
RestartPreventExitStatus=42
SuccessExitStatus=42
User=ubuntu
RuntimeDirectory=flux
RuntimeDirectoryMode=0755
StateDirectory=flux
StateDirectoryMode=0700
PermissionsStartOnly=true
# ExecStartPre=/usr/bin/loginctl enable-linger flux
# ExecStartPre=bash -c 'systemctl start user@$(id -u flux).service'

#
# Delegate cgroup control to user flux, so that systemd doesn't reset
#  cgroups for flux initiated processes, and to allow (some) cgroup
#  manipulation as user flux.
#
Delegate=yes

[Install]
WantedBy=multi-user.target
EOF
sudo mv /tmp/flux.service /lib/systemd/system/flux.service

# See the README.md for commands how to set this manually without systemd
sudo systemctl daemon-reload
sudo systemctl restart flux.service
sudo systemctl status flux.service

# Just sanity check we own everything still
sudo chown -R $USER /home/ubuntu

# Not sure why it's not taking my URI request above!
export FLUX_URI=local:///home/ubuntu/run/flux/local
echo "export FLUX_URI=local:///home/ubuntu/run/flux/local" >> /home/ubuntu/.bashrc

# Try librdmacm
sudo sysctl net.ipv4.conf.all.accept_local=1
sudo mknod /dev/infiniband/rdma_cm c 231 255
sudo chmod oug+w /dev/infiniband/rdma_cm

# Install osu benchmarks
export PATH=/opt/amazon/openmpi/bin:$PATH
cd /opt
OSU_VERSION=5.8
wget http://mvapich.cse.ohio-state.edu/download/mvapich/osu-micro-benchmarks-$OSU_VERSION.tgz
tar zxvf ./osu-micro-benchmarks-5.8.tgz
cd osu-micro-benchmarks-5.8/
./configure CC=mpicc CXX=mpicxx
make -j 4 && sudo make install
echo "export PATH=$PATH:/usr/local/libexec/osu-micro-benchmarks/mpi/one-sided" >> /home/ubuntu/.bashrc
echo "export PATH=$PATH:/usr/local/libexec/osu-micro-benchmarks/mpi/collective" >> /home/ubuntu/.bashrc
echo "export PATH=$PATH:/usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt" >> /home/ubuntu/.bashrc
echo "export PATH=$PATH:/usr/local/libexec/osu-micro-benchmarks/mpi/startup" >> /home/ubuntu/.bashrc

# Install nerdctl - these are steps shared between host and worker
wget https://github.com/containerd/nerdctl/releases/download/v2.0.0-beta.5/nerdctl-full-2.0.0-beta.5-linux-arm64.tar.gz
tar Cxzvvf /home/ubuntu/.local/ nerdctl-full-2.0.0-beta.5-linux-arm64.tar.gz
export PATH=$PATH:/home/ubuntu/.local/bin
export XDG_RUNTIME_DIR=/run/user/1000
export CONTAINER_ENGINE=nerdctl
echo "export PATH=$PATH:/home/ubuntu/.local/bin" >> /home/ubuntu/.bashrc
echo "export XDG_RUNTIME_DIR=/run/user/1000" >> /home/ubuntu/.bashrc
echo "export CONTAINER_ENGINE=nerdctl" >> /home/ubuntu/.bashrc

# Remove the old usernetes and clone the new!
rm -rf /home/ubuntu/usernetes
git clone -b testing-bypass https://github.com/rse-ops/usernetes /home/ubuntu/usernetes

# This has a customized exec start
cp /home/ubuntu/usernetes/extra/containerd-rootless-setuptool.sh /home/ubuntu/.local/bin/containerd-rootless-setuptool.sh

# mkdir -p /home/ubuntu/.docker/run
cd /home/ubuntu
sudo chown -R $USER /home/ubuntu
cd /home/ubuntu/usernetes
