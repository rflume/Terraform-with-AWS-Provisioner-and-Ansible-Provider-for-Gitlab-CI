# Terraform with AWS Provider and Ansible Provisioner for Gitlab CI

This Docker images is basen on the official `hashicorp/terraform:light` Terraform image and extends it with the [Terraform AWS Provider](https://github.com/terraform-providers/terraform-provider-aws/releases) and [Ansible Provisioner by radekg](https://github.com/radekg/terraform-provisioner-ansible).

**It is intended for the use as base image for [GitLab CI pipelines](https://docs.gitlab.com/ce/ci/quick_start/README.html).** You can read my full article on about how to use the image [on Medium.com](...). <!-- LINK TO BE ADDED! -->

The image is build as [Docker Multi-Stage Build](https://docs.docker.com/develop/develop-images/multistage-build/), which required Docker Engine `v17.05` or higher.

## Default Versions

The image needs to be build with Docker `build-args`, which default to the following versions:

* Terraform: `latest` (depends on the Terraform version of `hashicorp/terraform:light`)
* AWS Provisioner: `2.5.0`
* Ansible Provisioner: `2.1.2`

You can overwrite the versions of both the AWS Provisioner and the Ansible Provider within the `docker build` command:

```bash
docker build -t terraform-aws-ansible --build-arg AWS_PROVIDER_VERSION=2.1.1 --build-arg ANSIBLE_PROVISIONER_VERSION=2.1.1 .
```

The availailable versions can be found here:

* [AWS Provider Versions](https://github.com/terraform-providers/terraform-provider-aws/releases)
* [Ansible Provisioner Versions](https://github.com/radekg/terraform-provisioner-ansible/releases)

## Required Secrets

The image can be used to automate your Infrastructure creation with Gitlab CI pipelines. It is therefor required to provide both AWS credentials and login data of the user that the Ansible provisioner uses.

These must be provided as Gitlab CI secrets (project environment variables):

* `ANSIBLE_BECOME_PASS`: The password to become root on the hosts to be provisioned by ansible
* `ANSIBLE_VAULT_PASS`: The password the decrypt the [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html) (optional)
* `AWS_ACCESS_KEY_ID`: An AWS access key id to be used by the AWS provider
* `AWS_SECRET_ACCESS_KEY`: An AWS secret key to be used by the AWS provider
* `ID_RSA`: An SSH private key to be used by Ansible

## The Gitlab CI Pipeline Configuration

Tha actual pipeline can be configures as shown in this example:

```yml
image:
  name: rflume/terraform-aws-ansible:latest

stages:
  # Dev environment stages
  - validate dev
  - plan dev
  - apply dev
  # Prod environment stages
  - validate prod
  - plan prod
  - apply prod

variables:
  AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY

# Create files w/ required the secrets
before_script:
  - echo "$ID_RSA" > /root/.ssh/id_rsa
  - chmod 600 /root/.ssh/id_rsa_terraform
  - echo "$ANSIBLE_VAULT_PASS" > /etc/ansible/vault_password_file
  - chmod 0600 /etc/ansible/vault_password_file
  - echo "$ANSIBLE_BECOME_PASS" > /etc/ansible/become_pass
  - chmod 0666 /etc/ansible/become_pass

# Apply Terraform on DEV environment
validate:dev:
  stage: validate dev
  script:
    - cd environments/dev
    - terraform init -backend-config="access_key=$AWS_ACCESS_KEY_ID" -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"
    - terraform validate
    - cd ../..
  only:
    changes:
      - environments/dev/**/*
      - modules/**/*

plan:dev:
  stage: plan dev
  script:
    - cd environments/dev
    - terraform init -backend-config="access_key=$AWS_ACCESS_KEY_ID" -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"
    - terraform plan -out "planfile_dev"
    - cd ../..
  artifacts:
    paths:
      - environments/dev/planfile_dev
  only:
    changes:
      - environments/dev/**/*
      - modules/**/*

apply:dev:
  stage: apply dev
  script:
    - cd environments/dev
    - terraform init -backend-config="access_key=$AWS_ACCESS_KEY_ID" -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"
    - terraform apply -input=false "planfile_dev"
    - cd ../..
  dependencies:
    - plan:dev
  allow_failure: false
  only:
    refs:
      - master
    changes:
      - environments/dev/**/*
      - modules/**/*


# Apply Terraform on PROD environment
validate:prod:
  stage: validate prod
  script:
    - cd environments/prod
    - terraform init -backend-config="access_key=$AWS_ACCESS_KEY_ID" -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"
    - terraform validate
    - cd ../..
  only:
    changes:
      - environments/prod/**/*
      - modules/**/*

plan:prod:
  stage: plan prod
  script:
    - cd environments/prod
    - terraform init -backend-config="access_key=$AWS_ACCESS_KEY_ID" -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"
    - terraform plan -out "planfile_prod"
    - cd ../..
    - echo "CHANGES WON'T BE APPLIED UNLESS MERGED INTO BRANCH 'MASTER'! PLEASE CREATE A MERGE REQUEST..."
  artifacts:
    paths:
      - environments/prod/planfile_prod
  only:
    changes:
      - environments/prod/**/*
      - modules/**/*

apply:prod:
  stage: apply prod
  script:
    - cd environments/prod
    - terraform init -backend-config="access_key=$AWS_ACCESS_KEY_ID" -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"
    - terraform apply -input=false "planfile_prod"
    - cd ../..
  dependencies:
    - plan:prod
  when: manual
  allow_failure: false
  only:
    refs:
      - master
    changes:
      - environments/prod/**/*
      - modules/**/*
```

This pipeline required the manual confirmation of the changes, as defined by `when: manual`.

### Project Layout

The above pipeline works for the following project layout:

```text
projects/automation/terraform
├── .git
├── ansible-provisioning
│   └── roles
│       ├── my-general-role
│       │   ├── files
│       │   │   └── ...
│       │   ├── tasks
│       │   │   └── main.yml
│       │   └── templates
│       │       └── ...
├── environments
│   ├── dev
│   │   ├── files
│   │   │   └── user_data.sh
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tf
│   │   └── vars.tf
│   ├── prod
│   │   └── ...
├── modules
│   ├── my_module
│   │   ├── ansible
│   │   │   └── playbook
│   │   │       ├── group_vars
│   │   │       │   └── all
│   │   │       │       └── vault
│   │   │       ├── roles
│   │   │       │   └── playbook-specific-role
│   │   │       │       ├── tasks
│   │   │       │       │   └── main.yml
│   │   │       └── playbook.yml
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tf
│   │   └── vars.tf
├── .gitlab-ci.yml
└── ...
```

### Ansible Provisioning

To provision a newly created resource *directly* within Terraform, the Ansible provisioner is included in the image. For more information on available parameters, checkout the [Github project by radekg](https://github.com/radekg/terraform-provisioner-ansible).

This is a brief example on how to use Ansible provisioning with this Docker image:

```t
# ec2 instance
resource "aws_instance" "default" {
  ...
  user_data = "${var.user_data}" # within the userdata, a terraform user is created on the instance as which Ansible will connect ($ID_RSA is it's respective private key)
  ...
}

# instance provisioner
resource "null_resource" "default_provisioner" {
  triggers {
    default_instance_id = "${aws_instance.default.id}"
  }

  connection {
    host        = "${aws_instance.default.public_ip}"       # use the 'aws_eip.[...].public_ip if an EIP is assigned to the instance!
    type        = "ssh"
    user        = "terraform"                               # as created in 'user_data'
    private_key = "${file("/root/.ssh/id_rsa_terraform")}"  # created from projects env vars in the 'before_script' section of the pipline
  }

  # set hostname
  provisioner "remote-exec" {
    inline = [
      "echo '${file("/etc/ansible/become_pass")}' | sudo -S su",
      "echo '127.0.0.1 ${aws_instance.default.tags.Name}' | sudo tee -a /etc/hosts",
      "sudo hostnamectl set-hostname ${aws_instance.default.tags.Name}",
    ]
  }

  # ansible provisioner
  provisioner "ansible" {
    plays {
      playbook = {
        file_path = "${path.module}/ansible/playbook/playbook.yml"

        roles_path = [
          "${path.module}/../../../../../ansible-provisioning/roles", # Looks weird, feels weird, but is required as the module's base path is within '.terraform/.../.../.../'!
        ]
      }

      hosts         = ["${aws_instance.default.public_ip}"]         # possibly aws_eip.default.public_ip
      become        = true
      become_method = "sudo"
      become_user   = "root"

      extra_vars = {
        ...
        ansible_become_pass = "${file("/etc/ansible/become_pass")}" # created from projects env vars in the 'before_script' section of the pipline
      }

      vault_password_file = "/etc/ansible/vault_password_file"      # created from projects env vars in the 'before_script' section of the pipline
    }

    ansible_ssh_settings {
      connect_timeout_seconds = 20
      connection_attempts     = 3
      ssh_keyscan_timeout     = 60
    }
  }
}
```
