#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Leaves the disk small and every runner instance booting as a first boot.

apt-get -y autoremove --purge
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
journalctl --rotate
journalctl --vacuum-time=1s
find /var/log -type f -name '*.log' -exec truncate --size 0 {} +
rm -f /etc/ssh/ssh_host_*
# The build logged in with a throwaway key; it must not ship.
rm -f /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys
rm -f /root/.bash_history /home/*/.bash_history
cloud-init clean --logs --machine-id
fstrim --all || true
