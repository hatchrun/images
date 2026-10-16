#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

# Gates an image on its Trivy scan.
#
# Fails when the scan saw no packages, which means it did not read the
# filesystem, or when an operating system package has a HIGH or CRITICAL
# vulnerability with a fix: the build upgrades every package, so a fixable
# one means the image is stale.
#
# Code that vendors ship inside their own releases, such as the Node.js
# packages bundled with the GitHub runner or the Go libraries in Docker's
# plugins, only changes with a new vendor release. Its fixable HIGH and
# CRITICAL vulnerabilities are listed but do not fail the build; they also
# reach GitHub code scanning through the SARIF upload.
#
# Usage: check-scan.sh SCAN_JSON

set -euo pipefail

scan=$1

packages=$(jq '[.Results[]?.Packages[]?] | length' "${scan}")
if [ "${packages}" -eq 0 ]; then
  echo "${scan} lists no packages" >&2
  exit 1
fi

fixable() {
  jq -r --arg class "$1" '[.Results[]? | select(.Class == $class) | .Target as $target
    | .Vulnerabilities[]?
    | select((.Severity == "HIGH" or .Severity == "CRITICAL") and (.FixedVersion // "") != "")
    | "\(.Severity) \(.VulnerabilityID) \(.PkgName) \(.InstalledVersion) -> \(.FixedVersion) (\($target))"]
    | unique | .[]' "${scan}"
}

vendored=$( (fixable lang-pkgs; fixable binary) | sort -u)
if [ -n "${vendored}" ]; then
  echo "fixable HIGH or CRITICAL vulnerabilities in vendored code, fixed by vendor releases:" >&2
  echo "${vendored}" >&2
fi

os=$(fixable os-pkgs)
if [ -n "${os}" ]; then
  echo "fixable HIGH or CRITICAL vulnerabilities in operating system packages:" >&2
  echo "${os}" >&2
  exit 1
fi

echo "${packages} packages, no fixable HIGH or CRITICAL vulnerability in operating system packages"
