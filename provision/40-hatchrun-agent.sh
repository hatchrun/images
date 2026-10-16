#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

# hatchrun-agent runs the one job of the instance and powers it off.

arch=$(dpkg --print-architecture)
deb="hatchrun-agent_${AGENT_VERSION}_${arch}.deb"
base="https://github.com/hatchrun/hatchrun/releases/download/v${AGENT_VERSION}"

cd /tmp
curl -fsSL -O "${base}/${deb}"
curl -fsSL -O "${base}/SHA256SUMS"
grep " ${deb}$" SHA256SUMS | sha256sum --check --strict -
apt-get -y install "./${deb}"
rm "${deb}" SHA256SUMS
systemctl enable hatchrun-agent.service
