#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Scans the finished filesystem for vulnerabilities and records every
# package in /tmp/hatchrun-scan.json, then removes Trivy so it is not part
# of the image. Packer downloads the result and gates the build on it;
# 90-cleanup.sh removes it.

case "$(dpkg --print-architecture)" in
  amd64) archive="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" sha256=${TRIVY_SHA256_LINUX_X64} ;;
  arm64) archive="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz" sha256=${TRIVY_SHA256_LINUX_ARM64} ;;
esac

# /tmp is RAM on Ubuntu 26.04, and Trivy's database alone unpacks to about
# a gigabyte; on a 4 GB builder that runs out of memory.
work=$(mktemp -d -p /var/tmp)
curl -fsSL -o "${work}/${archive}" \
  "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${archive}"
echo "${sha256}  ${work}/${archive}" | sha256sum --check --strict -
tar -xzf "${work}/${archive}" -C "${work}" trivy

TRIVY_DISABLE_TELEMETRY=true "${work}/trivy" rootfs \
  --skip-version-check \
  --cache-dir "${work}/cache" \
  --scanners vuln \
  --list-all-pkgs \
  --skip-dirs /proc,/sys,/dev,/run,/tmp,/var/tmp \
  --format json \
  --output /tmp/hatchrun-scan.json \
  /

packages=$(jq '[.Results[]?.Packages[]?] | length' /tmp/hatchrun-scan.json)
echo "trivy found ${packages} packages"
if [ "${packages}" -eq 0 ]; then
  echo "trivy found no packages, so the scan did not see the filesystem" >&2
  exit 1
fi

rm -rf "${work}"
