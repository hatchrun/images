# hatchrun images

Runner AMIs for [hatchrun](https://github.com/hatchrun/hatchrun): small,
fast-booting Ubuntu 26.04 images (x64 and arm64) that stay compatible with
GitHub hosted runners where workflows depend on it: the `runner` user
(uid 1001, passwordless sudo), `/opt/hostedtoolcache`, `ImageOS`, rootful
Docker with Buildx, and preinstalled toolchains that `setup-*` actions pick
up without downloading.

Every build runs a compatibility suite of common actions and Docker
workloads before the AMI is published. Images are rebuilt weekly and
published as public AMIs with an SBOM and a vulnerability scan. You can
also build them in your own AWS account with the same pipeline.

Status: early development. Public AMIs are published to every region
enabled by default; each release's `manifest.json` lists their ids.

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

The root volume is 10 GB and unencrypted, so the AMI can be made public.
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

Each release lists the AMI id of every region and architecture in
`manifest.json`, with a build provenance attestation:

```sh
gh attestation verify manifest.json --repo hatchrun/images
```

## AWS Marketplace

Each architecture is an AWS Marketplace product, because a product
version holds a single AMI. Builds run in us-east-1, the only region
Marketplace takes source AMIs from, and every build is submitted as a
new version of both products
([`scripts/marketplace-version.sh`](scripts/marketplace-version.sh)).
Marketplace copies the AMI into its catalog through the
`hatchrun-marketplace-ingestion` role, scans it and serves it in every
region. The build role may add versions and nothing else; creating,
pricing and publishing the products stays a manual step in the
Marketplace Management Portal.

The `marketplace` job runs once the `MARKETPLACE_PRODUCT_AMD64` and
`MARKETPLACE_PRODUCT_ARM64` variables of the `image-build` environment
hold the product ids.

## Cost

A build runs a c7i.large or c7g.large for about 20 minutes. What costs
money over time is snapshot storage in every region the AMI is copied
to, so the workflow keeps only the newest version per architecture and
deregisters the rest with their snapshots ([`scripts/prune.sh`](scripts/prune.sh)).
AWS also allows an account only 5 public AMIs per region by default,
and a build adds two.
An image that fails the scan is never made or copied.

## Before you commit

Run `pre-commit install` once after cloning. The hook runs gitleaks on
staged changes with the rules in `.gitleaks.toml` and stops the commit
when it finds a secret or a Cloudflare or AWS account ID. CI scans the
full history with the same rules. Pass account IDs through CI secrets
or variables; a finding that is not a secret goes in `.gitleaksignore`
by fingerprint, with a comment saying why.

## Licence

Apache License, Version 2.0. See [LICENSE](LICENSE).
