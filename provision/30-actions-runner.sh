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

# hatchrun-agent sends cache requests to its own proxy by renaming these
# variables in the worker to ZCTIONS_*, and leaves the worker alone
# unless each occurs exactly once. A runner release that moves or
# duplicates one would quietly send every job back to GitHub's cache,
# so it fails the build here. .NET keeps string literals in UTF-16LE.
python3 - bin/Runner.Worker.dll <<'EOF'
import sys

dll = open(sys.argv[1], "rb").read()
wrong = False
for name in ("ACTIONS_CACHE_URL", "ACTIONS_RESULTS_URL", "ACTIONS_CACHE_SERVICE_V2"):
    count = dll.count(name.encode("utf-16-le"))
    print(f"{name} occurs {count} times in the runner worker")
    wrong |= count != 1
if wrong:
    sys.exit("hatchrun-agent patches the runner only when each occurs exactly once")
EOF

./bin/installdependencies.sh
chown -R runner:runner /home/runner
