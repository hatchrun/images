#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# The runner user matches hosted runners: uid 1001, passwordless sudo and
# the same groups, so workflows that chown to 1001 or call sudo work.

useradd --uid 1001 --create-home --shell /bin/bash runner
usermod --append --groups adm,docker,systemd-journal,users runner
echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner
chmod 0440 /etc/sudoers.d/runner
visudo --check --file /etc/sudoers.d/runner
