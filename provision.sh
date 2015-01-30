#!/bin/bash

# Variables passed in from terraform, see aws-vpc.tf, the "remote-exec" provisioner
AWS_KEY_ID=${1}
AWS_ACCESS_KEY=${2}
REGION=${3}
VPC=${4}
BOSH_SUBNET=${5}
IPMASK=${6}
BASTION_AZ=${7}
BASTION_ID=${8}
BOSH_TYPE=${9}
BOSH_VERSION=${10}
BOSH_SECURITY_GROUP_NAME=${11}
AWS_KEYPAIR_NAME=${12}

# Prepare the jumpbox to be able to install ruby and git-based bosh and cf repos
cd $HOME

sudo apt-get update
sudo apt-get install -y git vim-nox unzip mercurial -y

# Generate the key that will be used to ssh between the inception server and the
# microbosh machine
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

chmod 600 ~/.ssh/${AWS_KEYPAIR_NAME}.pem

# Install BOSH CLI, bosh-bootstrap, spiff and other helpful plugins/tools
curl -s https://raw.githubusercontent.com/cloudfoundry-community/traveling-bosh/master/scripts/installer http://bosh-cli.cloudfoundry.org | sudo bash
export PATH=$PATH:/usr/bin/traveling-bosh

update_profile() {
  file="$HOME/.bashrc"
  source_line=$1

  cat $file | grep "$source_line" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "$source_line" >> $file
  fi
}

# We use fog below, and bosh-bootstrap uses it as well
cat <<EOF > ~/.fog
:default:
    :aws_access_key_id: $AWS_KEY_ID
    :aws_secret_access_key: $AWS_ACCESS_KEY
    :region: $REGION
EOF

# This volume is created using terraform in aws-bosh.tf
sudo /sbin/mkfs.ext4 /dev/xvdc
sudo /sbin/e2label /dev/xvdc workspace
echo 'LABEL=workspace /home/ubuntu/workspace ext4 defaults,discard 0 0' | sudo tee -a /etc/fstab
mkdir -p /home/ubuntu/workspace
sudo mount -a
sudo chown -R ubuntu:ubuntu /home/ubuntu/workspace

# As long as we have a large volume to work with, we'll move /tmp over there
# You can always use a bigger /tmp
sudo rsync -avq /tmp/ /home/ubuntu/workspace/tmp/
sudo rm -fR /tmp
sudo ln -s /home/ubuntu/workspace/tmp /tmp

# bosh-bootstrap handles provisioning the microbosh machine and installing bosh
# on it. This is very nice of bosh-bootstrap. Everyone make sure to thank bosh-bootstrap
mkdir -p {bin,workspace/deployments,workspace/tools,workspace/deployments/bosh-bootstrap}
pushd workspace/deployments
cat <<EOF > settings.yml
---
bosh:
  name: bosh-${VPC}
provider:
  name: aws
  credentials:
    provider: AWS
    aws_access_key_id: ${AWS_KEY_ID}
    aws_secret_access_key: ${AWS_ACCESS_KEY}
  region: ${REGION}
address:
  vpc_id: ${VPC}
  subnet_id: ${BOSH_SUBNET}
  ip: ${IPMASK}.1.4
EOF

if [[ "${BOSH_TYPE}" = "ruby" ]]; then
  bosh bootstrap deploy

  # We've hardcoded the IP of the microbosh machine, because convenience
  bosh -n target https://${IPMASK}.1.4:25555
  bosh login admin admin
fi
popd

# Using go 1.3.3 as currently preferred go version for some BOSH projects
cd /tmp
rm -rf go*
wget https://storage.googleapis.com/golang/go1.3.3.linux-amd64.tar.gz
tar xfz go1.3.3.linux-amd64.tar.gz
sudo mv go /usr/local/go
update_profile 'export GOROOT=/usr/local/go'
mkdir -p $HOME/go
update_profile 'export GOPATH=$HOME/go'
update_profile 'export PATH=$PATH:$GOROOT/bin'
update_profile 'export PATH=$PATH:$GOPATH/bin'

if [[ "${BOSH_TYPE}" = "golang" ]]; then
  export GOROOT=/usr/local/go
  export GOPATH=$HOME/go
  export PATH=$PATH:$GOROOT/bin
  export PATH=$PATH:$GOPATH/bin
  mkdir -p $GOPATH/bin/
  go get -d github.com/cloudfoundry/bosh-micro-cli
  pushd $GOPATH/src/github.com/cloudfoundry/bosh-micro-cli
  ./bin/build

  # packages required to compile CPI's ruby
  sudo apt-get install -y build-essential zlibc zlib1g-dev
  # packages required to compile/install CPI
  sudo apt-get install -y openssl libxslt-dev libxml2-dev libssl-dev \
            libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3


  mv out/bosh-micro $GOPATH/bin/
  popd

  mkdir -p ~/workspace/stemcells
  pushd ~/workspace/stemcells
    wget https://s3.amazonaws.com/bosh-jenkins-artifacts/bosh-stemcell/aws/bosh-stemcell-${BOSH_VERSION}-aws-xen-ubuntu-trusty-go_agent.tgz
    STEMCELL_PATH=$(pwd)/bosh-stemcell-${BOSH_VERSION}-aws-xen-ubuntu-trusty-go_agent.tgz
  popd

  mkdir -p ~/workspace/releases
  pushd ~/workspace/releases
    wget https://s3.amazonaws.com/bosh-jenkins-artifacts/release/bosh-${BOSH_VERSION}.tgz
    RELEASE_PATH=$(pwd)/bosh-${BOSH_VERSION}.tgz

    wget https://community-shared-boshreleases.s3.amazonaws.com/boshrelease-bosh-aws-cpi-1.tgz
    CPI_PATH=$(pwd)/boshrelease-bosh-aws-cpi-1.tgz
  popd

  mkdir -p ~/workspace/deployments/microbosh
  pushd ~/workspace/deployments/microbosh
    cat <<EOF > bosh.yml
---
name: micro-aws-redis

networks:
- name: default
  type: manual
  cloud_properties:
    subnet: $BOSH_SUBNET
    range: $IPMASK.0.0/24
    reserved: [$IPMASK.1.1-$IPMASK.1.3]
    static: [$IPMASK.1.4]

resource_pools:
- name: default
  network: default
  cloud_properties:
    instance_type: m3.large

cloud_provider:
  release: bosh-aws-cpi
  ssh_tunnel:
    host: $IPMASK.1.4
    port: 22
    user: vcap
    private_key: /home/ubuntu/.ssh/$AWS_KEYPAIR_NAME.pem
  registry: &registry
    username: admin
    password: admin
    port: 6901
    host: localhost
  mbus: https://admin:admin@$IPMASK.1.4:6868
  properties: # properties that are saved in registry by CPI for the agent
    blobstore:
      provider: local
      path: /var/vcap/micro_bosh/data/cache
    registry: *registry
    ntp:
      - 0.pool.ntp.org
      - 1.pool.ntp.org
    aws: &aws
      access_key_id: $AWS_KEY_ID
      secret_access_key: $AWS_ACCESS_KEY
      default_key_name: $AWS_KEYPAIR_NAME
      default_security_groups: [$BOSH_SECURITY_GROUP_NAME]
      region: $REGION
      ec2_private_key: ~/.ssh/$AWS_KEYPAIR_NAME.pem
    agent:
      mbus: https://admin:admin@$IPMASK.1.4:6868

jobs:
- name: bosh
  instances: 1
  templates:
  - name: nats
    release: bosh
  - name: postgres
    release: bosh
  - name: redis
    release: bosh
  - name: powerdns
    release: bosh
  - name: blobstore
    release: bosh
  - name: director
    release: bosh
  - name: health_monitor
    release: bosh
  - name: registry
    release: bosh
  networks:
  - name: default
    static_ips:
    - 10.10.1.4
  properties:
    aws: *aws
    nats:
      user: "nats"
      password: "nats"
      auth_timeout: 3
      address: "127.0.0.1"
    postgres:
      user: "postgres"
      password: "postges"
      host: "127.0.0.1"
      database: "bosh"
      port: 5432
    redis:
      address: "127.0.0.1"
      password: "redis"
      port: 25255
    blobstore:
      address: "127.0.0.1"
      director:
        user: "director"
        password: "director"
      agent:
        user: "agent"
        password: "agent"
      provider: "dav"
    dns:
      address: 10.10.1.4
      domain_name: "microbosh"
      db:
        user: "postgres"
        password: "postges"
        host: "127.0.0.1"
        database: "bosh"
        port: 5432
        adapter: "postgres"
    ntp: []
    director:
      address: "127.0.0.1"
      name: "micro"
      port: 25555
      db:
        user: "postgres"
        password: "postges"
        host: "127.0.0.1"
        database: "bosh"
        port: 5432
        adapter: "postgres"
      backend_port: 25556
    registry:
      address: 10.10.1.4
      http:
        user: "admin"
        password: "admin"
        port: 25777
      db:
        user: "postgres"
        password: "postgres"
        host: "127.0.0.1"
        database: "bosh"
        port: 5432
        adapter: "postgres"
    hm:
      http:
        user: "hm"
        password: "hm"
      director_account:
        user: "admin"
        password: "admin"
      intervals:
        log_stats: 300
        agent_timeout: 180
        rogue_agent_alert: 180
EOF
    bosh-micro deployment bosh.yml
    bosh-micro deploy $STEMCELL_PATH $CPI_PATH $RELEASE_PATH

    # We've hardcoded the IP of the microbosh machine, because convenience
    bosh -n target https://${IPMASK}.1.4:25555
    bosh login admin admin
  popd
fi
