#!/usr/bin/env bash
set -euo pipefail

# Quick Node/npm checks: no package downloads or application test suite.
node --version
npm --version
npx --version
node -e 'if (process.versions.node.split(".")[0] !== "22") process.exit(1); console.log("Node 22 execution: OK")'

python -m pip check
python - <<'PY'
import importlib
import sys

assert sys.prefix == '/opt/ansible', sys.prefix
assert not any(p == '/usr/lib/python3/dist-packages' for p in sys.path), sys.path
for name in (
    'cryptography', 'winrm', 'kerberos', 'gssapi', 'requests',
    'requests_kerberos', 'requests_credssp', 'passlib', 'msrest',
    'msrestazure', 'pyVmomi', 'markdown2', 'pymssql', 'proxmoxer',
    'netaddr', 'jmespath', 'hvac', 'azure.identity', 'azure.cli.core',
    'azure.mgmt.datalake.store', 'azure.mgmt.datalake.analytics',
    'yaml', 'boto3',
):
    importlib.import_module(name)
from passlib.hash import sha512_crypt
assert sha512_crypt.verify('smoke-test', sha512_crypt.hash('smoke-test'))
print('Python imports, venv isolation and password hashing: OK')
PY

for collection in azure.azcollection community.general community.hashi_vault \
    community.proxmox community.vmware community.windows; do
    ansible-galaxy collection list "$collection" | grep -F "$collection"
done
# Load representative module documentation to catch collection/plugin issues.
for module in azure.azcollection.azure_rm_virtualmachine \
    community.proxmox.proxmox_kvm community.vmware.vmware_guest \
    community.windows.win_disk_facts community.hashi_vault.vault_read \
    community.general.ini_file; do
    ansible-doc --type module "$module" > /dev/null
done
if command -v gcc > /dev/null; then
    echo 'Compiler unexpectedly present in final image' >&2
    exit 1
fi
ansible --version
terraform version
packer version
vault version
az version
ovftool --version
for executable in make openssl ssh sshpass genisoimage xorriso klist; do
    command -v "$executable"
done

# Prove localhost uses this venv, not /usr/bin/python3.
ansible localhost -i localhost, -c local -m ansible.builtin.ping \
    -e ansible_python_interpreter=/opt/ansible/bin/python

# Exercise actual OVF parsing/conversion, not only CLI startup.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/smoke.vmx" <<'VMX'
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "17"
displayName = "docker-pataz-smoke"
guestOS = "ubuntu-64"
memsize = "128"
numvcpus = "1"
VMX
ovftool "$tmpdir/smoke.vmx" "$tmpdir/smoke.ovf"
test -s "$tmpdir/smoke.ovf"
ovftool "$tmpdir/smoke.ovf" "$tmpdir/roundtrip.vmx"
test -s "$tmpdir/roundtrip.vmx"
echo 'OVF local conversion round-trip: OK'
