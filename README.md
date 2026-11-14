# docker-pataz

Ubuntu 24.04 **Noble**, `linux/amd64` infrastructure automation toolbox:

- Terraform 1.17.2, Packer 1.16.2, Vault 2.2.2
- Latest compatible Ansible and Azure, Windows, VMware, Vault and Proxmox collections
- Azure CLI from Microsoft's signed Noble apt repository
- VMware OVF Tool 4.6.3
- SSH/Kerberos, ISO tools, `make`, and `openssl`

Published image: <https://hub.docker.com/r/andif888/docker-pataz>

## Build and test

```sh
docker build --pull --no-cache --platform linux/amd64 -t docker-pataz:noble .
docker run --rm --network none docker-pataz:noble docker-pataz-smoke-test
```

`--pull` refreshes the Ubuntu base; `--no-cache` reruns package/collection
resolution. Without the latter, cached layers can retain older dependencies.
Latest means newest **compatible** with Python 3.12 and the selected Azure
collection's constraints, not necessarily the absolute newest upstream release.
The Python packages and collections intentionally remain unpinned. Builds at
different times may differ; deploy a tested image by **registry digest** for an
immutable rollback point. Release tags alone are not intrinsically immutable.

Only amd64 is supported: the OVF download is x86_64-only. An ARM build fails
explicitly instead of silently mixing incompatible binaries. An Intel/AMD host
can omit `--platform`; ARM hosts need amd64 emulation.

## Python and localhost Ansible

Ansible uses an isolated venv at `/opt/ansible`, exposed through `PATH`.
Ubuntu's `/usr/bin/python3` remains distribution-managed. There is no
`--break-system-packages` or `--system-site-packages` workaround.

For localhost tasks using these dependencies:

```yaml
ansible_python_interpreter: /opt/ansible/bin/python
```

Set this for localhost only, not globally for remote guests. Python scripts
with a `/usr/bin/python3` shebang bypass the venv; use the venv interpreter when
those scripts require the toolbox's libraries. Collections are installed at
`/opt/ansible/collections`, independent of Python's site-packages layout.
Azure CLI has its own apt-managed Python environment; its installation does
not substitute for the Azure SDK requirements in the Ansible venv.

## Runtime and privilege

Compiler/development headers and download archives stay in the builder stage.
Runtime `make` and `openssl` remain for compatibility; `gcc` is not shipped.
The root default is preserved from the existing provisioning image, **not** a
recommendation to run every task as root. For jobs not requiring root, supply
`--user "$(id -u):$(id -g)"`, a writable HOME and a workspace bind mount appropriate
to your job. Never bake credentials into the image or mount the Docker socket.

The smoke test verifies imports, isolated interpreter selection, password
hashing, collections/module documentation, compiler absence, CLI startup,
localhost Ansible and a local VMX → OVF → VMX
conversion. CI repeats it on the **final image with networking disabled**.
Real Azure/VMware/Kerberos endpoint operations still need separately authorized
integration tests and credentials; a smoke test is not their substitute.

## Version inventory and publishing

Every image contains `/usr/local/share/docker-pataz/` with:

- `pip-freeze.txt`: resolved Python packages, including bootstrap tools
- `collections.txt`: installed collection versions
- `os-packages.txt`: installed apt packages
- `azure-version.json`: Azure CLI version

These are receipts, **not an input lock file or SBOM**. Native tool downloads
are checked against `checksums.sha256`; update the version and its trusted
checksum together. HashiCorp hashes were retrieved from each release's official
SHA256SUMS. The OVF hash records the existing owner-hosted ZIP and detects
subsequent changes; it is not independent vendor signature verification.

Pull requests build/test without registry credentials or publishing. Existing
release publication remains release-triggered: build, test, then log in to
Docker Hub and push the **same tested image**, without re-resolving dependencies.
No GHCR publication has been added. See [design decisions](docs/noble-design.md).
