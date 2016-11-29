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

function log() {
  echo "--> $1"
}

# Prepare the jumpbox to be able to install ruby and git-based bosh and cf repos
cd $HOME

log "Installing dependencies"
sudo apt-get update --fix-missing
sudo apt-get install -y git unzip

log "Installing RVM and Ruby 2.3.0"
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
curl -sSL https://get.rvm.io | bash -s stable --ruby=2.3.0
source /home/ubuntu/.rvm/scripts/rvm
# Fix for RVM root .gem dir
sudo chown ubuntu:ubuntu ~/.gem -R
gem install bundler   --no-rdoc --no-ri

log "Generate the key that will be used to ssh between the inception server and the# microbosh machine"
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

log "Installing spiff"
wget -qq https://github.com/cloudfoundry-incubator/spiff/releases/download/v1.0.7/spiff_linux_amd64.zip
unzip -q -o spiff_linux_amd64.zip
sudo mv spiff /usr/bin/
rm spiff_linux_amd64.zip

# We use fog below, and bosh-bootstrap uses it as well
log "Configuring Fog"
cat <<EOF > ~/.fog
:default:
    :aws_access_key_id: $AWS_KEY_ID
    :aws_secret_access_key: $AWS_ACCESS_KEY
    :region: $REGION
EOF

# This volume is created using terraform in aws-bosh.tf
log "Creating volume for workspace"
sudo /sbin/mkfs.ext4 /dev/xvdc
sudo /sbin/e2label /dev/xvdc workspace
echo 'LABEL=workspace /home/ubuntu/workspace ext4 defaults,discard 0 0' | sudo tee -a /etc/fstab
mkdir -p /home/ubuntu/workspace
sudo mount -a
sudo chown -R ubuntu:ubuntu /home/ubuntu/workspace

# As long as we have a large volume to work with, we'll move /tmp over there
# You can always use a bigger /tmp
log "Move /tmp to workspace"
sudo rsync -avq /tmp/ /home/ubuntu/workspace/tmp/
sudo rm -fR /tmp
sudo ln -s /home/ubuntu/workspace/tmp /tmp

# Install BOSH CLI, bosh-bootstrap, spiff and other helpful plugins/tools
log "Installing BOSH CLI and bosh-bootstrap"
gem install httpclient --version=2.7.1 --no-rdoc --no-ri
gem install builder --version=3.1.4 --no-rdoc --no-ri
gem install aws-sdk-v1 --version=1.60.2 --no-rdoc  --no-ri
gem install bosh_cli --no-ri --no-rdoc

log "Cloning bosh-bootstrap"
pushd workspace
git clone https://github.com/cloudfoundry-community/bosh-bootstrap.git
cd bosh-bootstrap
gem install bundler
bundle
gem build bosh-bootstrap.gemspec
gem install --local bosh-bootstrap*.gem
popd

# bosh-bootstrap handles provisioning the microbosh machine and installing bosh
# on it. This is very nice of bosh-bootstrap. Everyone make sure to thank bosh-bootstrap
log "Prepare deployment for bosh-bootstrap"
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

  log "Boostrap deploy"
  bosh bootstrap deploy

  # We've hardcoded the IP of the microbosh machine, because convenience
  log "Target the director"
  bosh -n target https://${IPMASK}.1.4:25555
  log "Login as admin"
  bosh login admin admin
fi
popd
