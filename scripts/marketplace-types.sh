#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Adds every instance type a runner can use to the AWS Marketplace
# product of an architecture, with an hourly dimension priced at $0 on
# the product's free public offer. EC2 launches a Marketplace AMI only on
# the types its product lists, and Marketplace does not add new EC2
# types by itself.
#
#   marketplace-types.sh PRODUCT_ID OFFER_ID ARCH
#
# A runner type is current generation, Nitro, not bare metal and has no
# GPU, FPGA or other accelerator, in any region the account has enabled.
# Types already on the product stay. Set DRY_RUN=1 to print the change
# set instead of starting it.
#
# Marketplace rejects some types that EC2 lists, and fails the whole
# change set naming them. The script drops those and tries again, and
# skips types its change sets of the last 30 days were refused, so a
# rejected type costs one failed change set a month.

product=$1
offer=$2
arch=$3

case "${arch}" in
amd64) ec2_arch=x86_64 ;;
arm64) ec2_arch=arm64 ;;
*)
  echo "unknown architecture ${arch}" >&2
  exit 1
  ;;
esac

name_prefix="hatchrun-types-${arch}-"
attempts=5

catalog() {
  aws marketplace-catalog "$@" --region us-east-1 --catalog AWSMarketplace --output json
}

# Prints the types an INVALID_INSTANCE_TYPES error of a described change
# set names, one per line. The message reads
# "Following instance types '[i8g.48xlarge, r9g.medium]' are not valid".
invalid_types() {
  jq -r '.ChangeSet[].ErrorDetailList[]?
    | select(.ErrorCode == "INVALID_INSTANCE_TYPES")
    | .ErrorMessage | capture("\\[(?<types>[^]]*)\\]").types
    | split(", ")[]'
}

# Prints the runner types of one region, one per line.
region_types() {
  aws ec2 describe-instance-types \
    --region "$1" \
    --filters \
    Name=current-generation,Values=true \
    Name=hypervisor,Values=nitro \
    Name=bare-metal,Values=false \
    "Name=processor-info.supported-architecture,Values=${ec2_arch}" \
    --output json |
    jq -r '.InstanceTypes[]
      | select(.GpuInfo == null and .FpgaInfo == null and .InferenceAcceleratorInfo == null
          and .NeuronInfo == null and .MediaAcceleratorInfo == null)
      | .InstanceType'
}

dir=$(mktemp -d)
trap 'rm -rf "${dir}"' EXIT
pids=()
for region in $(aws ec2 describe-regions --region us-east-1 --query 'Regions[].RegionName' --output text); do
  region_types "${region}" > "${dir}/${region}" &
  pids+=($!)
done
# A region that fails to answer must fail the run, or its types would
# look like they are gone.
for pid in "${pids[@]}"; do
  wait "${pid}"
done
wanted=$(sort -u "${dir}"/* | jq -R . | jq -sc .)
echo "${ec2_arch}: $(jq length <<< "${wanted}") current runner types across enabled regions"

since=$(jq -rn 'now - 30 * 86400 | todate')
failed=$(catalog list-change-sets \
  --filter-list "$(jq -cn --arg product "${product}" --arg since "${since}" \
    '[{Name: "EntityId", ValueList: [$product]}, {Name: "Status", ValueList: ["FAILED"]},
      {Name: "AfterStartTime", ValueList: [$since]}]')" |
  jq -r --arg prefix "${name_prefix}" \
    '.ChangeSetSummaryList[] | select(.ChangeSetName | startswith($prefix)) | .ChangeSetId')
rejected=$(for id in ${failed}; do
  catalog describe-change-set --change-set-id "${id}" | invalid_types
done | sort -u | jq -R . | jq -sc .)
if [ "$(jq length <<< "${rejected}")" -gt 0 ]; then
  echo "skipping types Marketplace refused in the last 30 days: $(jq -r 'join(" ")' <<< "${rejected}")"
fi

for ((attempt = 1; attempt <= attempts; attempt++)); do
  entity=$(catalog describe-entity --entity-id "${product}" | jq .DetailsDocument)
  rates=$(catalog describe-entity --entity-id "${offer}" |
    jq '[.DetailsDocument.Terms[] | select(.Type == "UsageBasedPricingTerm") | .RateCards[].RateCard[] | {key: .DimensionKey, price: (.Price | tonumber)}]')

  # The offer's rate card replaces the old one, so it lists every
  # dimension, old and new. A card that misses a dimension or charges
  # for one is rewritten.
  plan=$(jq -n \
    --argjson wanted "${wanted}" \
    --argjson rejected "${rejected}" \
    --argjson entity "${entity}" \
    --argjson rates "${rates}" \
    '($entity.Compatibility.AvailableInstanceTypes // []) as $available
    | ([$entity.Dimensions[]?.Key]) as $dimensions
    | ($wanted - $available - $rejected | sort) as $types
    | (($available + $types | unique) - $dimensions | sort) as $new_dimensions
    | ($dimensions + $new_dimensions | unique) as $priced
    | {types: $types, dimensions: $new_dimensions, priced: $priced,
       reprice: (([$rates[].key] | unique) != $priced or any($rates[]; .price != 0))}')

  types=$(jq -r '.types | join(" ")' <<< "${plan}")
  dimensions=$(jq -r '.dimensions | join(" ")' <<< "${plan}")
  if [ -z "${types}" ] && [ -z "${dimensions}" ] && [ "$(jq .reprice <<< "${plan}")" = false ]; then
    echo "${product} lists every runner type, each priced at \$0"
    exit 0
  fi
  echo "adding types: ${types:-none}"
  echo "adding dimensions: ${dimensions:-none}"

  change_set=$(jq -c --arg product "${product}" --arg offer "${offer}" \
    '[if (.types | length) > 0 then {
       ChangeType: "AddInstanceTypes",
       Entity: {Type: "AmiProduct@1.0", Identifier: $product},
       DetailsDocument: {InstanceTypes: .types}
     } else empty end,
     if (.dimensions | length) > 0 then {
       ChangeType: "AddDimensions",
       Entity: {Type: "AmiProduct@1.0", Identifier: $product},
       DetailsDocument: [.dimensions[] | {Key: ., Name: ., Description: ., Types: ["Metered"], Unit: "Hrs"}]
     } else empty end,
     {
       ChangeType: "UpdatePricingTerms",
       Entity: {Type: "Offer@1.0", Identifier: $offer},
       DetailsDocument: {
         PricingModel: "Free",
         Terms: [{
           Type: "UsageBasedPricingTerm",
           CurrencyCode: "USD",
           RateCards: [{RateCard: [.priced[] | {DimensionKey: ., Price: "0.00"}]}]
         }]
       }
     }]' <<< "${plan}")

  if [ "${DRY_RUN:-0}" = 1 ]; then
    jq . <<< "${change_set}"
    exit 0
  fi

  id=$(catalog start-change-set \
    --change-set-name "${name_prefix}$(date -u +%Y%m%d.%H%M%S)" \
    --change-set "${change_set}" | jq -r .ChangeSetId)
  echo "change set ${id}"

  # Instance type changes finish in under a minute.
  deadline=$(($(date +%s) + 900))
  while :; do
    result=$(catalog describe-change-set --change-set-id "${id}")
    status=$(jq -r .Status <<< "${result}")
    case "${status}" in
    PREPARING | APPLYING) ;;
    *) break ;;
    esac
    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "::error::change set ${id} is still ${status} after 15 minutes"
      exit 1
    fi
    sleep 15
  done

  if [ "${status}" = SUCCEEDED ]; then
    echo "change set ${id} succeeded"
    exit 0
  fi

  invalid=$(invalid_types <<< "${result}" | jq -R . | jq -sc .)
  others=$(jq '[.ChangeSet[].ErrorDetailList[]? | select(.ErrorCode != "INVALID_INSTANCE_TYPES")] | length' <<< "${result}")
  if [ "$(jq length <<< "${invalid}")" -eq 0 ] || [ "${others}" -gt 0 ]; then
    echo "::error::change set ${id} ${status}: $(jq -r .FailureCode <<< "${result}")"
    jq -r '.ChangeSet[].ErrorDetailList[]? | "\(.ErrorCode): \(.ErrorMessage)"' <<< "${result}"
    exit 1
  fi
  echo "::notice::Marketplace refused $(jq -r 'join(" ")' <<< "${invalid}") for ${product}; trying again without them"
  rejected=$(jq -c --argjson invalid "${invalid}" '. + $invalid | unique' <<< "${rejected}")
done

echo "::error::${product} still has types Marketplace refuses after ${attempts} change sets"
exit 1
