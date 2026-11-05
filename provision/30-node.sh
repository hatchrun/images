#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

# Node 20 and 24 in /home/runner/externals/<node20|node24>, where
# hatchrun-agent looks for the Node that runs JavaScript actions.

# shellcheck disable=SC2034  # read through indirect expansion below
case "$(dpkg --print-architecture)" in
  amd64)
    arch=x64
    sha256_20=${NODE20_SHA256_X64}
    sha256_24=${NODE24_SHA256_X64}
    ;;
  arm64)
    arch=arm64
    sha256_20=${NODE20_SHA256_ARM64}
    sha256_24=${NODE24_SHA256_ARM64}
    ;;
esac

install -d -o runner -g runner /home/runner/externals
cd /tmp
for major in 20 24; do
  version_var=NODE${major}_VERSION
  sha256_var=sha256_${major}
  version=${!version_var}
  tarball="node-v${version}-linux-${arch}.tar.xz"
  curl -fsSL -o "${tarball}" "https://nodejs.org/dist/v${version}/${tarball}"
  echo "${!sha256_var}  ${tarball}" | sha256sum --check --strict -
  mkdir "/home/runner/externals/node${major}"
  tar -xJf "${tarball}" --strip-components=1 -C "/home/runner/externals/node${major}"
  rm "${tarball}"
done
chown -R runner:runner /home/runner/externals
