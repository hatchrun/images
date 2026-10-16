#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

# setup-* actions install into and look up toolchains from this directory.

install -d -o runner -g runner -m 0755 /opt/hostedtoolcache
