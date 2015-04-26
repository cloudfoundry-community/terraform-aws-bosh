.PHONY: all plan apply destroy

all: sshkey plan apply

sshkey:
	mkdir -p ssh
	[[ ! -f ssh/id_rsa ]] && ssh-keygen -f ssh/id_rsa -N '' || echo Key pair already exists

plan:
	terraform get -update
	terraform plan -module-depth=-1 -var-file terraform.tfvars -out terraform.tfplan

apply:
	terraform apply -var-file terraform.tfvars

destroy:
	terraform plan -destroy -var-file terraform.tfvars -out terraform.tfplan
	terraform apply terraform.tfplan

clean:
	rm -f terraform.tfplan
	rm -f terraform.tfstate
	rm -fR .terraform/
