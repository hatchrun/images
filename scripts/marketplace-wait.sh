#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

# Waits for an AWS Marketplace change set to finish and fails when
# Marketplace rejected it. Validation errors come back within seconds;
# the security scan of a new version can take hours.
#
#   marketplace-wait.sh CHANGE_SET_ID [TIMEOUT_SECONDS]
#
# A change set still running after TIMEOUT_SECONDS (default 3 hours, less
# than the build role's 4-hour session) fails as well: the release needs
# the AMIs Marketplace serves once it succeeds.

change_set=$1
timeout=${2:-10800}
interval=60

describe() {
  aws marketplace-catalog describe-change-set \
    --region us-east-1 \
    --catalog AWSMarketplace \
    --change-set-id "${change_set}" \
    --output json
}

deadline=$(($(date +%s) + timeout))
while :; do
  result=$(describe)
  status=$(jq -r .Status <<< "${result}")
  case "${status}" in
  SUCCEEDED)
    echo "change set ${change_set} succeeded"
    exit 0
    ;;
  FAILED | CANCELLED)
    echo "::error::change set ${change_set} ${status}: $(jq -r .FailureCode <<< "${result}")"
    # Each error names its code and, for scan findings, a report URL.
    jq -r '.ChangeSet[].ErrorDetailList[]? | "\(.ErrorCode): \(.ErrorMessage)"' <<< "${result}"
    exit 1
    ;;
  esac
  if [ "$(date +%s)" -ge "${deadline}" ]; then
    echo "::error::change set ${change_set} is still ${status} after $((timeout / 60)) minutes; follow it in the AWS Marketplace Management Portal"
    exit 1
  fi
  sleep "${interval}"
done
