terraform-aws-bosh
==================

This project will create an AWS VPC with subnets/route tables, a bastion VM (aka jumpbox/inception server), NAT (for outbound traffic), and a Micro BOSH.

Architecture
------------

This terraform project will deploy the following networking and instances (pretty diagram from https://ide.visualops.io):

![](http://cl.ly/image/1u1F462W2W0p/terraform-aws-bosh_architecture.png)

We rely on one other terraform repository:

-	[terraform-aws-vpc](https://github.com/cloudfoundry-community/terraform-aws-vpc) repo creates the base VPC infrastructure, including a bastion subnet, the`microbosh` subnet, a NAT server, various route tables, and the VPC itself

This repository then creates a bastion VM and uses it to bootstrap a Micro BOSH (using the [bosh-bootstrap](https://github.com/cloudfoundry-community/bosh-bootstrap) project) into one of the private subnets.

To access the BOSH, first SSH into the bastion VM.

Deploy
------

### Prerequisites

The one step that isn't automated is the creation of SSH keys. We are waiting for that feature to be [added to terraform](https://github.com/hashicorp/terraform/issues/28). An AWS SSH Key need to be created in desired region prior to running the following commands. Note the name of the key and the path to the pem/private key file for use further down.

You **must** being using at least terraform version 0.3.6. Follow the `make dev` [build instructions](https://github.com/hashicorp/terraform/#developing-terraform) to ensure plugins are built too.

```
$ terraform -v
Terraform v0.3.6.dev
```

Optionally for using the `Unattended Install` instruction, install git.

### Setup

```bash
git clone https://github.com/cloudfoundry-community/terraform-aws-bosh
cd terraform-aws-cf-bosh
cp terraform.tfvars.example terraform.tfvars
```

Next, edit `terraform.tfvars` using your text editor and fill out the variables with your own values (AWS credentials, AWS region, etc).

### Deploy

```bash
make plan
make apply
```

The final output might look like:

```
Outputs:

aws_internet_gateway_id              = igw-6439f501
aws_route_table_private_id           = rtb-51e94a34
aws_route_table_public_id            = rtb-49e94a2c
aws_subnet_bastion                   = subnet-1419a771
aws_subnet_bastion_availability_zone = us-west-2a
aws_vpc_id                           = vpc-b72581d2
bastion_ip                           = 54.1.2.3
```

After Initial Install
---------------------

At the end of the output of the terraform run, there will be a section called `Outputs` that will have at least `bastion_ip` and an IP address. If not, or if you cleared the terminal without noting it, you can log into the AWS console and look for an instance called `bastion`, with the `bastion` security group. Use the public IP associated with that instance, and ssh in as the ubuntu user, using the ssh key listed as `aws_key_path` in your configuration (if you used the Unattended Install).

```
ssh -i ~/.ssh/example.pem ubuntu@54.1.2.3
```

You can also access the "Outputs" from above using `terraform output`:

```
ssh ubuntu@$(terraform output bastion_ip)
```

Once inside you can access your BOSH.

```
$ bosh target
Current target is https://10.10.1.4:25555 (vpc-b72581d2-keypair)

$ bosh status
Config
  /home/ubuntu/.bosh_config

Director
  Name       vpc-b72581d2-keypair
  URL        https://10.10.1.4:25555
  ...
```

### Cleanup / Tear down

Terraform does not yet quite cleanup after itself.

First, using the AWS Console you must manually delete all Instances (VMs).

Second, run `make destroy`.

Finally, run `make clean`.
