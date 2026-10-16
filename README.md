# hatchrun images

Runner AMIs for [hatchrun](https://github.com/hatchrun/hatchrun): small,
fast-booting Ubuntu 26.04 images (x64 and arm64) that stay compatible with
GitHub hosted runners where workflows depend on it: the `runner` user
(uid 1001, passwordless sudo), `/opt/hostedtoolcache`, `ImageOS`, rootful
Docker with Buildx, and preinstalled toolchains that `setup-*` actions pick
up without downloading.

Every build runs a compatibility suite of common actions and Docker
workloads before the AMI is published. Images are rebuilt weekly and
published through AWS Marketplace, free, with an SBOM and a
vulnerability scan: [amd64](https://aws.amazon.com/marketplace/pp/prodview-znhn62372z6jq)
and [arm64](https://aws.amazon.com/marketplace/pp/prodview-nchg6i6uzlfr2).
An AWS account subscribes to each once before it can launch them. You
can also build them in your own AWS account with the same pipeline.

Status: early development. Marketplace serves the images in every
region enabled by default; each release's `manifest.json` lists their
ids.

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
packer build -var arch=arm64 -var image_version=$(date -u +%Y%m%d.%H%M) \
  -var runner_version=$RUNNER_VERSION -var agent_version=$AGENT_VERSION packer/
```

Every outside input is pinned in [`versions.env`](versions.env) or the
Packer template: the GitHub runner, hatchrun-agent and Trivy are checked
against their SHA-256 sums and Docker's signing key against its
fingerprint before anything is installed.

The image has:

- the `runner` user, uid 1001, in the `docker`, `adm`, `systemd-journal`
  and `users` groups, with passwordless sudo;
- the GitHub Actions runner in `/home/runner`, started by
  hatchrun-agent for exactly one job;
- Docker CE with Buildx and Compose;
- `ImageOS=ubuntu26`, `ImageVersion` and `/opt/hostedtoolcache` in
  `/etc/environment`, which the agent hands to the runner;
- no snapd, no unattended upgrades and no apt timers, so nothing changes
  the machine during a job.

The root volume is 10 GB and unencrypted, so AWS Marketplace can copy
the AMI.
Set the size and encryption in your launch template.

## Boot

A runner instance runs one job, so boot time is paid on every job. From
launch to the job's first step takes about 29 seconds on a t4g.medium
instance; the Ubuntu cloud image as provisioned took 71.

- cloud-init is disabled. Ubuntu orders it before every regular service
  and it held the agent back for about 20 seconds. A netplan file runs
  DHCP on the primary interface, `hatchrun-ssh-key.service` installs
  the launch key pair for `ubuntu`, and `hatchrun-growroot.service`
  grows the root file system in the background. Scripts in user data do
  not run; hatchrun-agent reads user data itself.
- A volume made from a snapshot fetches each block from S3 on first
  read. `hatchrun-prefetch.service` reads the runner's and Docker's
  files many at a time early in boot, which took the runner's start
  from 16 seconds to 3.
- Docker starts after the agent, while the runner connects to GitHub,
  instead of competing with it for the disk.
- Services a single-job machine never uses are disabled.

## Job cache

For profiles with the `cache` extra, hatchrun-agent serves the GitHub
cache from a proxy on the instance, backed by the tenant's S3 bucket.
It points the runner at the proxy by renaming `ACTIONS_CACHE_URL`,
`ACTIONS_RESULTS_URL` and `ACTIONS_CACHE_SERVICE_V2` in
`bin/Runner.Worker.dll`, and only when each occurs exactly once. The
build checks the same after installing the runner and fails otherwise,
since a runner release that moves one would send every job back to
GitHub's cache without an error.

## Security

Before the AMI is made, Trivy scans the builder's own filesystem and is
then removed. The build stops when the scan lists no packages, which
means it did not see the filesystem, or finds a HIGH or CRITICAL
vulnerability with a fix in an operating system package: packages are
upgraded at build time, so a fixable one means something is stale.
Findings in code vendored by the runner or Docker plugins are reported
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

Each release lists the AMI id Marketplace serves in every region, per
architecture, in `manifest.json`, with a build provenance attestation:

```sh
gh attestation verify manifest.json --repo hatchrun/images
```

## AWS Marketplace

AWS Marketplace is how the images are distributed. Each architecture is
a product, because a product version holds a single AMI. Builds make a
private AMI in us-east-1, the only region Marketplace takes source AMIs
from, and submit it as a new version of its product
([`scripts/marketplace-version.sh`](scripts/marketplace-version.sh)).
Marketplace copies the AMI into its catalog through the
`hatchrun-marketplace-ingestion` role, scans it and serves it in every
region under the alias `/aws/service/marketplace/PRODUCT_ID/VERSION`.
Once the scan passes, the build reads that alias in each region for the
release ([`scripts/marketplace-amis.sh`](scripts/marketplace-amis.sh)).
The build role may add versions and nothing else; creating, pricing and
publishing the products stays a manual step in the Marketplace
Management Portal.

The `MARKETPLACE_PRODUCT_AMD64` and `MARKETPLACE_PRODUCT_ARM64`
variables of the `image-build` environment hold the product ids. A build
without them fails, as does a version Marketplace rejects or has not
scanned within 3 hours.

## Cost

A build runs a c7i.large or c7g.large for about 20 minutes. Marketplace
stores and serves the copies in every region, so the only storage the
build account pays for is the source AMI in us-east-1. The workflow
keeps the newest version per architecture and deregisters the rest with
their snapshots ([`scripts/prune.sh`](scripts/prune.sh)).
An image that fails the scan is never made or submitted.

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
