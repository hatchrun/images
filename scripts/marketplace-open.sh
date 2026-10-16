#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

# Lists the AWS Marketplace change sets still open (PREPARING or
# APPLYING) on the given products, one "CHANGE_SET_ID AMI_ID" line each.
# A product takes one open change set at a time, and Marketplace reads
# the source AMI while the change set scans it.
#
#   marketplace-open.sh PRODUCT_ID...

for product in "$@"; do
  ids=$(aws marketplace-catalog list-change-sets \
    --region us-east-1 \
    --catalog AWSMarketplace \
    --filter-list "$(jq -cn --arg product "${product}" \
      '[{Name: "EntityId", ValueList: [$product]}, {Name: "Status", ValueList: ["PREPARING", "APPLYING"]}]')" \
    --query 'ChangeSetSummaryList[].ChangeSetId' --output text)
  for id in ${ids}; do
    [ "${id}" = None ] && continue
    # Details is the change as a JSON string, an object for most changes
    # and an array for some. A change without an AMI, such as a listing
    # edit, prints "-".
    aws marketplace-catalog describe-change-set \
      --region us-east-1 \
      --catalog AWSMarketplace \
      --change-set-id "${id}" \
      --output json |
      jq -r --arg id "${id}" '[.ChangeSet[].Details | fromjson | objects
        | .DeliveryOptions[]?.Details.AmiDeliveryOptionDetails.AmiSource.AmiId // empty]
        | if length == 0 then ["-"] else . end | .[] | "\($id) \(.)"'
  done
done
