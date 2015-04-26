#!/bin/bash

mkdir -p ssh
[[ ! -f ssh/id_rsa ]] && ssh-keygen -f ssh/id_rsa -N '' || echo Key pair already exists
cat >aws_public_key.tf <<EOF
variable "aws_public_key" {
  default = "$(cat ssh/id_rsa.pub)"
}
EOF
