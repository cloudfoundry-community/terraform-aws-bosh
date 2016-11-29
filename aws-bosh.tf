provider "aws" {
	access_key = "${var.aws_access_key}"
	secret_key = "${var.aws_secret_key}"
	region = "${var.aws_region}"
}

module "vpc" {
  source = "github.com/cloudfoundry-community/terraform-aws-vpc"
  network = "${var.network}"
  aws_key_name = "${var.aws_key_name}"
  aws_access_key = "${var.aws_access_key}"
  aws_secret_key = "${var.aws_secret_key}"
  aws_region = "${var.aws_region}"
  aws_key_path = "${var.aws_key_path}"
}

output "aws_vpc_id" {
  value = "${module.vpc.aws_vpc_id}"
}

output "aws_internet_gateway_id" {
  value = "${module.vpc.aws_internet_gateway_id}"
}

output "aws_route_table_public_id" {
  value = "${module.vpc.aws_route_table_public_id}"
}

output "aws_route_table_private_id" {
  value = "${module.vpc.aws_route_table_private_id}"
}

output "aws_subnet_bastion" {
  value = "${module.vpc.bastion_subnet}"
}

output "aws_subnet_bastion_availability_zone" {
  value = "${module.vpc.aws_subnet_bastion_availability_zone}"
}

output "aws_key_path" {
	value = "${var.aws_key_path}"
}

resource "aws_instance" "bastion" {
  ami = "${lookup(var.aws_ubuntu_ami, var.aws_region)}"
  instance_type = "m3.medium"
  key_name = "${var.aws_key_name}"
  associate_public_ip_address = true
  security_groups = ["${module.vpc.aws_security_group_bastion_id}"]
  subnet_id = "${module.vpc.bastion_subnet}"

	ebs_block_device {
		device_name = "xvdc"
		volume_size = "40"
	}

  tags {
   Name = "bastion"
  }

  connection {
    user = "ubuntu"
    key_file = "${var.aws_key_path}"
  }

  provisioner "file" {
    source = "${path.module}/provision.sh"
    destination = "/home/ubuntu/provision.sh"
  }

  provisioner "remote-exec" {
    inline = [
        "chmod +x /home/ubuntu/provision.sh",
        "/home/ubuntu/provision.sh ${var.aws_access_key} ${var.aws_secret_key} ${var.aws_region} ${module.vpc.aws_vpc_id} ${module.vpc.aws_subnet_microbosh_id} ${var.network} ${aws_instance.bastion.availability_zone} ${aws_instance.bastion.id} ${var.bosh_type}",
    ]
  }

}

output "bastion_ip" {
  value = "${aws_instance.bastion.public_ip}"
}
