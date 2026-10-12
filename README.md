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

## Cost

A build runs a c7i.large or c7g.large for about 20 minutes. What costs
money over time is snapshot storage in every region the AMI is copied
to, so the workflow keeps the newest two versions per architecture and
deregisters the rest with their snapshots ([`scripts/prune.sh`](scripts/prune.sh)).
An image that fails the scan is never made or copied.

## Licence

Apache License, Version 2.0. See [LICENSE](LICENSE).
