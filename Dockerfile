FROM ubuntu:jammy
LABEL maintainer="andif888"
ENV DEBIAN_FRONTEND noninteractive
ENV TF_VERSION 1.8.3
ENV PACKER_VERSION 1.10.3
ENV VAULT_VERSION 1.16.2

ENV pip_packages "ansible cryptography pywinrm kerberos requests_kerberos requests-credssp passlib msrest msrestazure PyVmomi markdown2 pymssql proxmoxer"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        gcc \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        krb5-user \
        krb5-config \
        libffi-dev \
        libkrb5-dev \
        libssl-dev \
        locales \
        lsb-release \
        mkisofs \
        openssh-client \
        python3-dev \
        python3-gssapi \
        python3-pip \
        python3-netaddr \
        python3-jmespath \
        python3-setuptools \
        python3-wheel \
        python3-pymssql \
        python3-hvac \
        sshpass \
        unzip \
        xorriso \
    && rm -rf /var/lib/apt/lists/* \
    && rm -Rf /usr/share/doc && rm -Rf /usr/share/man \
    && apt-get clean

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8  
ENV LANGUAGE en_US:en  
ENV LC_ALL en_US.UTF-8

RUN pip3 install --upgrade pip \
    && pip3 install $pip_packages \
    && pip3 install 'ansible' \
    && ansible-galaxy collection install azure.azcollection community.general community.hashi_vault

RUN curl -O https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip \
    && unzip -o terraform_${TF_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm -f terraform_${TF_VERSION}_linux_amd64.zip \
    && chmod +x /usr/bin/terraform \
    && curl -O https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip \
    && unzip -o packer_${PACKER_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm -f packer_${PACKER_VERSION}_linux_amd64.zip \
    && chmod +x /usr/bin/packer \
    && curl -O https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip \
    && unzip -o vault_${VAULT_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm -f vault_${VAULT_VERSION}_linux_amd64.zip \
    && chmod +x /usr/bin/vault

RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

RUN curl -O https://vdc-download.vmware.com/vmwb-repository/dcr-public/8a93ce23-4f88-4ae8-b067-ae174291e98f/c609234d-59f2-4758-a113-0ec5bbe4b120/VMware-ovftool-4.6.2-22220919-lin.x86_64.zip \
    && unzip VMware-ovftool-4.6.2-22220919-lin.x86_64.zip -d /opt \
    && rm -f VMware-ovftool-4.6.2-22220919-lin.x86_64.zip \
    && ln -s /opt/ovftool/ovftool /usr/bin/ovftool

CMD    ["/bin/bash"]
