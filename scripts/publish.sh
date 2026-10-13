#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

# Makes every AMI of one image version public, in every enabled region.
#
# Packer builds the AMIs private. Sharing them in Packer happens before
# it tags them, so a failed share left untagged AMIs that the build role
# may not delete. Here the AMIs are already tagged: if sharing fails,
# prune.sh can still remove them.
#
# Usage: publish.sh VERSION

set -euo pipefail

version=$1

regions=$(aws ec2 describe-regions \
  --filters Name=opt-in-status,Values=opt-in-not-required,opted-in \
  --query 'Regions[].RegionName' --output text)

shared=0
for region in ${regions}; do
  amis=$(aws ec2 describe-images --region "${region}" --owners self \
    --filters "Name=tag:hatchrun:image-version,Values=${version}" \
    --query 'Images[].ImageId' --output text)
  for ami in ${amis}; do
    aws ec2 modify-image-attribute --region "${region}" --image-id "${ami}" \
      --launch-permission 'Add=[{Group=all}]'
    shared=$((shared + 1))
  done
done

if [ "${shared}" -eq 0 ]; then
  echo "no AMIs tagged with version ${version}" >&2
  exit 1
fi
echo "made ${shared} AMIs of ${version} public" >&2
