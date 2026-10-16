#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

# Base system: current packages, the tools GitHub hosted runners ship and
# workflows assume, and nothing that changes the machine under a job.

export DEBIAN_FRONTEND=noninteractive

# Runners live for one job. Background upgrades only slow boot and can
# take the dpkg lock a job needs.
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer
for package in snapd unattended-upgrades lxd-installer modemmanager; do
  if dpkg-query --show --showformat='${Status}' "${package}" 2>/dev/null | grep -q 'install ok installed'; then
    apt-get -y purge "${package}"
  fi
done

apt-get update
apt-get -y upgrade
apt-get -y install --no-install-recommends \
  build-essential ca-certificates curl file git git-lfs gnupg jq \
  lsb-release openssh-client pkg-config python3 python3-pip python3-venv \
  rsync sudo tar time unzip wget xz-utils zip zstd

# Read by the agent as the runner's whole environment, as on hosted runners.
cat >> /etc/environment <<'ENV'
ImageOS=ubuntu26
AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
RUNNER_TOOL_CACHE=/opt/hostedtoolcache
ENV
echo "ImageVersion=${IMAGE_VERSION}" >> /etc/environment
