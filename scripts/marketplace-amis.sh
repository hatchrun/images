#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

# Prints the AMIs AWS Marketplace serves for one version of a product as
# a JSON object of region to AMI id, read from the alias
# /aws/service/marketplace/PRODUCT_ID/VERSION in every region enabled by
# default. A region without the alias is left out.
#
#   marketplace-amis.sh PRODUCT_ID VERSION
#
# The alias can lag the change set that added the version by a few
# minutes, so us-east-1 is retried for up to 10 minutes first; a version
# Marketplace still does not serve there fails.

product=$1
version=$2
name="/aws/service/marketplace/${product}/${version}"

alias_in() {
  aws ssm get-parameter --region "$1" --name "${name}" \
    --query Parameter.Value --output text 2>/dev/null
}

for attempt in $(seq 20); do
  alias_in us-east-1 >/dev/null && break
  if [ "${attempt}" -eq 20 ]; then
    echo "::error::${name} is not in us-east-1 after 10 minutes" >&2
    exit 1
  fi
  sleep 30
done

regions=$(aws ec2 describe-regions \
  --filters Name=opt-in-status,Values=opt-in-not-required \
  --query 'Regions[].RegionName' --output text)

amis='{}'
for region in ${regions}; do
  if ami=$(alias_in "${region}"); then
    amis=$(jq --arg region "${region}" --arg ami "${ami}" '. + {($region): $ami}' <<< "${amis}")
  else
    echo "no ${name} in ${region}" >&2
  fi
done

jq -S . <<< "${amis}"
