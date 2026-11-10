# hatchrun images

CI AMIs for [hatchrun](https://github.com/hatchrun/hatchrun): small,
fast-booting Ubuntu 26.04 images (x64 and arm64) that stay compatible with
GitHub hosted runners where workflows depend on it: the `runner` user
(uid 1001, passwordless sudo), `/opt/hostedtoolcache`, `ImageOS`, rootful
Docker with Buildx, and preinstalled toolchains that `setup-*` actions pick
up without downloading.

Every build scans the image for vulnerabilities before the AMI is
published. Common actions and Docker workloads are checked by
[hatchrun/smoke-test](https://github.com/hatchrun/smoke-test) against
each release. Images are rebuilt weekly and released with an SBOM and
a vulnerability scan. hatchrun CI launches them from the account that
builds them. You can also build them in your own AWS account with the
same pipeline.

Status: early development. The build runs in us-east-1, where
hatchrun CI launches runners; each release's `manifest.json` lists the
AMI ids.

## Building

[Packer](https://developer.hashicorp.com/packer) builds the image from
[`packer/ubuntu.pkr.hcl`](packer/ubuntu.pkr.hcl). It boots the current
Ubuntu 26.04 cloud image, runs the scripts in [`provision/`](provision)
over SSH, scans the result and makes the AMI. SSH is open only to the
public address of the machine running Packer, for the length of the
build, with a throwaway key that is removed from the image.

```sh
. ./versions.env
packer init packer/
packer build -var arch=arm64 -var image_version=$(date -u +%Y%m%d.%H%M) packer/
```

Every outside input is pinned in [`versions.env`](versions.env) or the
Packer template: Node, hatchrun-agent and Trivy are checked
against their SHA-256 sums and Docker's signing key against its
fingerprint before anything is installed.

The image has:

- the `runner` user, uid 1001, in the `docker`, `adm`, `systemd-journal`
  and `users` groups, with passwordless sudo;
- Node 20 and 24 in `/home/runner/externals`, which hatchrun-agent
  uses to run JavaScript actions, and `/home/runner/work` as the job
  work directory;
- Docker CE with Buildx and Compose;
- `ImageOS=ubuntu26`, `ImageVersion` and `/opt/hostedtoolcache` in
  `/etc/environment`, which the agent hands to the job;
- no snapd, no unattended upgrades and no apt timers, so nothing changes
  the machine during a job.

The root volume is 10 GB and unencrypted in the AMI. Set the size and
encryption in your launch template; runners always launch with an
encrypted volume.

## Boot

A CI instance runs one job, so boot time is paid on every job. From
launch to the job's first step takes about 29 seconds on a t4g.medium
instance; the Ubuntu cloud image as provisioned took 71.

- cloud-init is disabled. Ubuntu orders it before every regular service
  and it held the agent back for about 20 seconds. A netplan file runs
  DHCP on the primary interface, `hatchrun-ssh-key.service` installs
  the launch key pair for `ubuntu`, and `hatchrun-growroot.service`
  grows the root file system in the background. Scripts in user data do
  not run; hatchrun-agent reads user data itself.
- A volume made from a snapshot fetches each block from S3 on first
  read. `hatchrun-prefetch.service` reads Node's and Docker's
  files many at a time early in boot.
- Docker starts after the agent, while the agent connects to hatchrun,
  instead of competing with it for the disk.
- Services a single-job machine never uses are disabled.

## Security

Before the AMI is made, Trivy scans the builder's own filesystem and is
then removed. The build stops when the scan lists no packages, which
means it did not see the filesystem, or finds a HIGH or CRITICAL
vulnerability with a fix in an operating system package: packages are
upgraded at build time, so a fixable one means something is stale.
Findings in code vendored by Node or Docker plugins are reported
but do not stop the build, since only their upstream releases can fix
them. The results go to GitHub code scanning and every release carries
a CycloneDX SBOM per architecture.

The [build workflow](.github/workflows/build.yml) reaches AWS through
GitHub's OIDC provider; no AWS keys are stored anywhere.
[`bootstrap/github-oidc.yml`](bootstrap/github-oidc.yml) creates the
role. Only `build.yml` on `main`, running in the protected
`image-build` environment, can assume it, matched on the repository's
immutable ids. The role launches nothing but the two small builder
instance types, in one region and with the build tag, and deletes only
images and snapshots the build tagged.

Each release lists the AMI id hatchrun CI launches, per architecture,
in `manifest.json`, with a build provenance attestation:

```sh
gh attestation verify manifest.json --repo hatchrun/images
```

## Distribution

Builds make a private AMI in us-east-1 and record its id in the
release. The build and the CI launcher run in the same AWS account, so
no copy, sharing or subscription step is involved: `hatchrun-cloud`
stores the AMI ids in its `images` table and `hatchrun-ci` launches
from them.

The images are not published publicly. To run them outside hatchrun,
build the image in your own account with the pipeline above.

## Cost

A build runs a c7i.large or c7g.large for about 20 minutes. The build
account stores the AMIs it launches in us-east-1: the newest two
versions per architecture, plus the AMIs of the previous release so it
stays launchable for a rollback. The workflow deregisters older versions
with their snapshots ([`scripts/prune.sh`](scripts/prune.sh)).
An image that fails the scan is never made or released.

## Before you commit

Run `pre-commit install` once after cloning. The hook runs gitleaks on
staged changes with the rules in `.gitleaks.toml` and stops the commit
when it finds a secret or a Cloudflare or AWS account ID. CI scans the
full history with the same rules. Pass account IDs through CI secrets
or variables; a finding that is not a secret goes in `.gitleaksignore`
by fingerprint, with a comment saying why.

## Licence

GNU Affero General Public License, version 3 only (AGPL-3.0-only). See
[LICENSE](LICENSE).
