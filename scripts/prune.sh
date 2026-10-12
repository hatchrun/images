#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

# Keeps the newest KEEP image versions per architecture in every enabled
# region and deregisters the rest with their snapshots, which are what
# costs money. Only AMIs this account owns and tagged by the build are
# touched.
#
# Usage: KEEP=2 prune.sh

set -euo pipefail

keep=${KEEP:-2}

regions=$(aws ec2 describe-regions \
  --filters Name=opt-in-status,Values=opt-in-not-required,opted-in \
  --query 'Regions[].RegionName' --output text)

for region in ${regions}; do
  for arch in amd64 arm64; do
    # Oldest first, so everything but the last KEEP lines goes.
    old=$(aws ec2 describe-images --region "${region}" --owners self \
      --filters "Name=tag:hatchrun:arch,Values=${arch}" Name=tag-key,Values=hatchrun:image-version \
      --query 'sort_by(Images, &CreationDate)[].ImageId' --output text \
      | tr '\t' '\n' | sed '/^$/d' \
      | awk -v keep="${keep}" '{ ids[NR] = $0 } END { for (i = 1; i <= NR - keep; i++) print ids[i] }')
    for ami in ${old}; do
      echo "deregistering ${region} ${ami}" >&2
      aws ec2 deregister-image --region "${region}" --image-id "${ami}" \
        --delete-associated-snapshots >/dev/null
    done
  done
done
