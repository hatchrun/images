#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

# Keeps the newest KEEP image versions per architecture in AWS_REGION,
# where the build makes its source AMIs, and deregisters the rest with
# their snapshots, which are what costs money. Only AMIs this account
# owns and tagged by the build are touched.
#
# An AMI that an open AWS Marketplace change set on one of PRODUCTS is
# still copying and scanning is kept as well, whatever its age: deleting
# it can fail the new Marketplace version.
#
# Usage: KEEP=2 PRODUCTS="prod-a prod-b" prune.sh
#
# Set DRY_RUN=1 to print what would be deregistered without doing it.

set -euo pipefail

keep=${KEEP:-2}
dry_run=${DRY_RUN:-0}

# shellcheck disable=SC2086 # PRODUCTS is a list of ids
scanning=$("$(dirname "$0")/marketplace-open.sh" ${PRODUCTS:-} | awk '{ print $2 }')

for arch in amd64 arm64; do
  # Oldest first, so everything but the last KEEP lines goes.
  old=$(aws ec2 describe-images --owners self \
    --filters "Name=tag:hatchrun:arch,Values=${arch}" Name=tag-key,Values=hatchrun:image-version \
    --query 'sort_by(Images, &CreationDate)[].ImageId' --output text \
    | tr '\t' '\n' | sed '/^$/d' \
    | awk -v keep="${keep}" '{ ids[NR] = $0 } END { for (i = 1; i <= NR - keep; i++) print ids[i] }')
  for ami in ${old}; do
    if grep -qxF "${ami}" <<< "${scanning}"; then
      echo "keeping ${ami}, AWS Marketplace is scanning it" >&2
      continue
    fi
    echo "deregistering ${ami}" >&2
    [ "${dry_run}" = 1 ] && continue
    aws ec2 deregister-image --image-id "${ami}" --delete-associated-snapshots >/dev/null
  done
done
