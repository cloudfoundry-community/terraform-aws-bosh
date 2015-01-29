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

# Prepare the jumpbox to be able to install ruby and git-based bosh and cf repos
cd $HOME

sudo apt-get update
sudo apt-get install -y git vim-nox unzip mercurial

# Generate the key that will be used to ssh between the inception server and the
# microbosh machine
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

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

  mv out/bosh-micro $GOPATH/bin/
  popd
fi
