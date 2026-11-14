# Noble migration: engineering decisions

Research checked 2026-11-14; source baseline `68c1af4`.

## Choose for this workload, not a generic "smallest container" checklist

This is an infrastructure toolbox, not a single-purpose web service. Preserve
its cloud SDKs, Kerberos, OVF, make/openssl and existing root compatibility.
Do not switch to Alpine/distroless: it changes libc/package compatibility and
conflicts with the requested Ubuntu base and x86_64 OVF binary.

- **Isolated venv over system-site-packages:** one visible Python dependency
  set, no apt/PyPI fallback or shadowing, PEP 668 compliance. Install gssapi,
  netaddr, jmespath and hvac in that environment rather than assuming Ubuntu
  modules remain visible. Python 3.12 removed distutils; bootstrap setuptools
  inside the venv instead of installing unavailable python3-distutils.
- **Multi-stage build:** runtime and builder share the same Noble base and
  Python path, making a copied venv viable. Compile Kerberos/GSSAPI with gcc
  and headers in the builder; keep their shared libraries in the final stage.
  Test the final stage, not just the builder, to detect missing runtime links.
- **Freshness vs reproducibility:** respect the owner's latest-compatible
  preference. Resolve libraries together with the installed Azure collection's
  requirements, run pip check, record versions and test. Do not claim floating
  inputs are reproducible. Promote the same tested artifact, then deploy its
  digest; full source rebuild reproducibility would require additional locks,
  apt snapshots and a base digest with an update process.
- **Native integrity:** commit expected hashes rather than downloading a hash
  beside its archive at build time. This detects unexpected artifact changes.
  Do not claim a hash obtained from the owner's mirror authenticates VMware.
- **Azure CLI:** explicit Microsoft's signed apt repository for Noble rather
  than executing a mutable installer script. Keep its interpreter separate
  from Ansible's Azure SDKs. Retain old Data Lake SDKs pending evidence that
  existing playbooks no longer use them.
- **Privileges:** preserve root by default to avoid breaking provisioning
  jobs; document non-root execution rather than silently changing bind-mount,
  HOME and privilege assumptions in an OS migration.
- **CI:** unprivileged pull_request event, read-only GitHub permissions, no
  registry secrets/push for validation. Pin Actions to inspected commit SHAs.
  Release publication is preserved but gated on final-image tests; push the
  exact loaded image rather than rebuilding latest dependencies after testing.
  Local conversion exercises OVF beyond --version. No remote infrastructure
  changes or credential-dependent tests are performed.

## Primary sources

- [Docker build best practices](https://docs.docker.com/build/building/best-practices/):
  multi-stage builds, official bases, minimal packages, apt update/install
  together, fresh rebuilds, dockerignore and CI tests.
- [Docker test before push](https://docs.docker.com/build/ci/github-actions/test-before-push/).
- [Externally managed Python environments](https://packaging.python.org/en/latest/specifications/externally-managed-environments/).
- [Python 3.12 changes](https://docs.python.org/3.12/whatsnew/3.12.html):
  distutils removal and setuptools no longer included automatically in venvs.
- [Ubuntu Noble package catalogue](https://packages.ubuntu.com/noble/).
- [Microsoft Azure CLI apt installation](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/Latest-version/includes/cli-install-linux-apt.md):
  Noble support, signed-by keyring/repository configuration.
- [Azure collection requirements](https://github.com/ansible-collections/azure#requirements).
- [GSSAPI build requirements](https://pypi.org/project/gssapi/): Kerberos headers
  and a C compiler; Linux wheels are not provided for the checked release.
- [pymssql](https://pypi.org/project/pymssql/): Python 3.12 wheels bundle FreeTDS.
- [OVF 4.6.3 release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-sdks-tools/8-0/release-notes/vmware-ovf-tool/vmware-ovf-tool-463-release-notes.html):
  recent Ubuntu support and a libnsl-related export issue. Verify conversion
  on Noble; do not guess that a CLI version check proves export compatibility.

## Verified local candidate (2026-11-14)

- Fresh Noble build succeeded; gssapi 1.12.0, kerberos 1.3.1 and krb5 0.10.0
  were compiled successfully in the builder stage.
- Final revision rebuilt and smoke-tested with `docker run --rm --network none`:
  imports, pip check, representative collection documentation, password hashing,
  localhost ping and VMX → OVF → VMX conversion all passed.
- Final runtime has neither gcc nor Python 3.12 development headers.
- Ansible 14.6.0 / core 2.21.6; apt Azure CLI 2.92.0, while the Azure collection
  constrains its separate venv azure-cli-core to 2.91.0.
- External upgraded collections include azure.azcollection 4.2.0,
  community.general 14.0.1 and community.vmware 7.0.0. Ansible's bundled
  collections can also appear in the inventory; the explicit collection path
  takes precedence. Retain the full Ansible distribution for compatibility
  with playbooks beyond the six explicitly named collections.
- Local image size: 5,175,702,898 bytes (about 5.18 GB decimal). This remains a
  broad SDK toolbox, not a small image: the full Ansible distribution and Azure
  collection dependencies dominate. Do not claim an unmeasured size reduction
  against the original image. Further reduction would require selecting fewer
  SDKs/collections and accepting a narrower workload scope.
- Docker build checks report no warnings; Bash syntax, YAML parsing,
  Actionlint 1.7.12 and git diff whitespace checks pass. Independent read-only
  review found no static blockers. GitHub runner validation is a separate gate.
- No image was pushed, release created, cloud endpoint contacted or guest changed.
