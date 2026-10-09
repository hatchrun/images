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

Status: early development, no public AMIs yet.

## Licence

Apache License, Version 2.0. See [LICENSE](LICENSE).
