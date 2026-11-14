# syntax=docker/dockerfile:1
# Track current patches within Node 22, without adopting a new major.
FROM node:22-bookworm-slim AS node-source

FROM ubuntu:noble AS runtime-base

LABEL maintainer="andif888" \
      org.opencontainers.image.source="https://github.com/andif888/docker-pataz" \
      org.opencontainers.image.description="Ubuntu Noble infrastructure automation toolbox"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

# Fail early instead of mixing an ARM OS with the x86_64-only OVF binary.
RUN test "${TARGETARCH:-$(dpkg --print-architecture)}" = amd64

ENV TF_VERSION=1.17.2 \
    PACKER_VERSION=1.16.2 \
    VAULT_VERSION=2.2.2 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    VIRTUAL_ENV=/opt/ansible \
    ANSIBLE_COLLECTIONS_PATH=/opt/ansible/collections
ENV PATH="/opt/ansible/bin:${PATH}"

# Runtime libraries, not Python development headers or compilers.
# make and openssl remain available for existing automation scripts.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        genisoimage \
        git \
        gnupg \
        jq \
        krb5-config \
        krb5-user \
        libffi8 \
        libgssapi-krb5-2 \
        libkrb5-3 \
        libnsl2 \
        libssl3t64 \
        locales \
        make \
        openssh-client \
        openssl \
        python3 \
        python3-venv \
        sshpass \
        xorriso \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI from Microsoft's signed Noble apt repository, rather
# than executing a mutable remote installation script. az owns its Python.
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl --fail --show-error --silent --location \
        https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
    && chmod 0644 /etc/apt/keyrings/microsoft.gpg \
    && printf '%s\n' \
        'Types: deb' \
        'URIs: https://packages.microsoft.com/repos/azure-cli/' \
        'Suites: noble' \
        'Components: main' \
        'Architectures: amd64' \
        'Signed-By: /etc/apt/keyrings/microsoft.gpg' \
        > /etc/apt/sources.list.d/azure-cli.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends azure-cli \
    && rm -rf /var/lib/apt/lists/*

FROM runtime-base AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        libffi-dev \
        libkrb5-dev \
        libssl-dev \
        python3-dev \
        unzip \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
COPY collections.yml /tmp/collections.yml

# Isolated venv: no PEP 668 override and no implicit apt Python imports.
# Select the newest versions compatible with Python and collection constraints.
RUN python3 -m venv "${VIRTUAL_ENV}" \
    && python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir --upgrade ansible \
    && ansible-galaxy collection install --upgrade \
        -p "${ANSIBLE_COLLECTIONS_PATH}" -r /tmp/collections.yml \
    && python -m pip install --no-cache-dir --upgrade \
        -r /tmp/requirements.txt \
        -r "${ANSIBLE_COLLECTIONS_PATH}/ansible_collections/azure/azcollection/requirements.txt" \
    && python -m pip check

# Fixed native tool versions, verified against checksums committed to Git.
COPY checksums.sha256 /tmp/checksums.sha256
RUN mkdir -p /tmp/downloads /opt/tool-binaries \
    && cd /tmp/downloads \
    && for spec in "terraform:${TF_VERSION}" "packer:${PACKER_VERSION}" "vault:${VAULT_VERSION}"; do \
        tool="${spec%%:*}"; version="${spec#*:}"; \
        archive="${tool}_${version}_linux_amd64.zip"; \
        curl --fail --show-error --silent --location --retry 3 \
            "https://releases.hashicorp.com/${tool}/${version}/${archive}" -o "${archive}"; \
    done \
    && curl --fail --show-error --silent --location --retry 3 \
        https://minio.iamroot.it/public/vmware/VMware-ovftool-4.6.3-24031167-lin.x86_64.zip \
        -o VMware-ovftool-4.6.3-24031167-lin.x86_64.zip \
    && sha256sum --check /tmp/checksums.sha256 \
    && for tool in terraform packer vault; do \
        unzip -j "${tool}_"'*.zip' "${tool}" -d /opt/tool-binaries; \
        chmod 0755 "/opt/tool-binaries/${tool}"; \
    done \
    && unzip -q VMware-ovftool-4.6.3-24031167-lin.x86_64.zip -d /opt \
    && rm -rf /tmp/downloads

FROM runtime-base AS final

# Keep these additions in the final stage so the Python builder stays cached.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libatomic1 libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Copy only Node and its bundled npm, not the source image's entrypoint,
# user, headers, Yarn, or unrelated /usr/local contents.
COPY --from=node-source /usr/local/bin/node /usr/local/bin/node
COPY --from=node-source /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

COPY --from=builder /opt/ansible /opt/ansible
COPY --from=builder /opt/tool-binaries/ /usr/local/bin/
COPY --from=builder /opt/ovftool /opt/ovftool
COPY --chmod=0755 scripts/smoke-test.sh /usr/local/bin/docker-pataz-smoke-test

RUN ln -s /opt/ovftool/ovftool /usr/local/bin/ovftool \
    && docker-pataz-smoke-test \
    && mkdir -p /usr/local/share/docker-pataz \
    && python -m pip freeze --all > /usr/local/share/docker-pataz/pip-freeze.txt \
    && ansible-galaxy collection list > /usr/local/share/docker-pataz/collections.txt \
    && dpkg-query -W > /usr/local/share/docker-pataz/os-packages.txt \
    && az version > /usr/local/share/docker-pataz/azure-version.json \
    && node --version > /usr/local/share/docker-pataz/node-version.txt \
    && npm --version > /usr/local/share/docker-pataz/npm-version.txt

# Preserve the existing root default for compatibility with provisioning jobs.
# Prefer --user for jobs that do not need root; see README for bind mounts.
CMD ["/bin/bash"]
