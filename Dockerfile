
# Multi-Stage builds require Docker Engine 17.05 or higher

# Build AWS provider
FROM ubuntu:xenial as builder

# Get available versions from: https://github.com/terraform-providers/terraform-provider-aws/releases
ARG AWS_PROVIDER_VERSION=2.5.0

ENV HOME /root
ENV GOPATH $HOME/go
ENV GOBIN $GOPATH/bin

RUN apt-get update &&\
    apt-get install -yqq software-properties-common \
                         git \
                         wget \
                         unzip \
                         build-essential &&\
    add-apt-repository ppa:longsleep/golang-backports &&\
    apt-get update &&\
    apt-get install -y golang-go &&\
    mkdir -p $GOPATH/src/github.com/terraform-providers &&\
    wget -O $HOME/terraform-provider-aws.zip https://github.com/terraform-providers/terraform-provider-aws/archive/v$AWS_PROVIDER_VERSION.zip &&\
    cd $GOPATH/src/github.com/terraform-providers/ &&\
    unzip $HOME/terraform-provider-aws.zip -d . &&\
    mv terraform-provider-aws-$AWS_PROVIDER_VERSION \
       terraform-provider-aws

WORKDIR $GOPATH/src/github.com/terraform-providers/terraform-provider-aws

RUN make build


# Build the actual image
FROM hashicorp/terraform:light

ARG AWS_PROVIDER_VERSION=2.5.0
# Get available versions from https://github.com/radekg/terraform-provisioner-ansible/releases
ARG ANSIBLE_PROVISIONER_VERSION=2.1.2

ENV GOBIN $GOPATH/bin
ENV PATH $GOPATH/bin:$PATH

RUN mkdir -p /root/.terraform.d/plugins

COPY --from=builder /root/go/bin/terraform-provider-aws $GOBIN/terraform-provider-aws_v$AWS_PROVIDER_VERSION

RUN wget -O /root/.terraform.d/plugins/terraform-provisioner-ansible_v$ANSIBLE_PROVISIONER_VERSION https://github.com/radekg/terraform-provisioner-ansible/releases/download/v${ANSIBLE_PROVISIONER_VERSION}/terraform-provisioner-ansible-linux-amd64_v${ANSIBLE_PROVISIONER_VERSION} &&\
    chmod 0755 $GOBIN/terraform-provider-aws_v$AWS_PROVIDER_VERSION &&\
    chmod 0755 /root/.terraform.d/plugins/terraform-provisioner-ansible_v$ANSIBLE_PROVISIONER_VERSION &&\
    apk add --update --no-cache \
        openssh \
        ansible \
        py-pip \
        py-netaddr &&\
    pip install --upgrade pip\
        botocore \
        boto \
        boto3 &&\
    rm -rf /var/cache/apk/* &&\
    mkdir -p /root/.ssh &&\
    chmod 0700 /root/.ssh &&\
    touch /root/.ssh/id_rsa_terraform &&\
    echo "    IdentityFile /root/.ssh/id_rsa_terraform" >> /etc/ssh/ssh_config &&\
    mkdir -p /etc/ansible &&\
    chmod 0700 /etc/ansible

ENTRYPOINT ["/bin/sh", "-c"]
