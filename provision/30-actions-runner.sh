#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# The GitHub Actions runner in /home/runner, where hatchrun-agent starts it.

case "$(dpkg --print-architecture)" in
  amd64) arch=x64 sha256=${RUNNER_SHA256_X64} ;;
  arm64) arch=arm64 sha256=${RUNNER_SHA256_ARM64} ;;
esac

cd /home/runner
curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${arch}-${RUNNER_VERSION}.tar.gz"
echo "${sha256}  runner.tar.gz" | sha256sum --check --strict -
tar -xzf runner.tar.gz
rm runner.tar.gz
./bin/installdependencies.sh
chown -R runner:runner /home/runner
