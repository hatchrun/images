#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Rootful Docker with Buildx and Compose from Docker's repository, as on
# hosted runners.

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
fingerprint=$(gpg --show-keys --with-colons /tmp/docker.asc | awk -F: '$1 == "fpr" { print $10; exit }')
if [ "${fingerprint}" != "${DOCKER_GPG_FINGERPRINT}" ]; then
  echo "unexpected Docker signing key ${fingerprint}" >&2
  exit 1
fi
gpg --dearmor -o /etc/apt/keyrings/docker.gpg /tmp/docker.asc
rm /tmp/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get -y install --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker.service containerd.service
