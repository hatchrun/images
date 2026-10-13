#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Submits a built AMI as a new version of its AWS Marketplace product.
# Marketplace copies the AMI into its catalog, scans it and serves it in
# every region, which takes from minutes to hours after this returns.
#
#   marketplace-version.sh PRODUCT_ID AMI_ID ARCH
#
# Reads IMAGE_VERSION, UBUNTU_RELEASE, RUNNER_VERSION, AGENT_VERSION and
# ACCESS_ROLE_ARN (the role Marketplace ingests the AMI through) from the
# environment. Set DRY_RUN=1 to validate the request without applying it.

product=$1
ami=$2
arch=$3

case "${arch}" in
amd64) instance_type=c7i.large ;;
arm64) instance_type=c7g.large ;;
*)
  echo "unknown architecture ${arch}" >&2
  exit 1
  ;;
esac

intent=APPLY
if [ "${DRY_RUN:-0}" = 1 ]; then
  intent=VALIDATE
fi

change_set=$(jq -n \
  --arg product "${product}" \
  --arg ami "${ami}" \
  --arg role "${ACCESS_ROLE_ARN}" \
  --arg version "${IMAGE_VERSION}" \
  --arg ubuntu "${UBUNTU_RELEASE}" \
  --arg runner "${RUNNER_VERSION}" \
  --arg agent "${AGENT_VERSION}" \
  --arg instance_type "${instance_type}" \
  '[{
    ChangeType: "AddDeliveryOptions",
    Entity: {Type: "AmiProduct@1.0", Identifier: $product},
    DetailsDocument: {
      Version: {
        VersionTitle: $version,
        ReleaseNotes: "Ubuntu \($ubuntu), GitHub Actions runner \($runner), hatchrun-agent \($agent). Release notes, SBOM and scan results: https://github.com/hatchrun/images/releases/tag/ubuntu26-\($version)"
      },
      DeliveryOptions: [{
        Details: {
          AmiDeliveryOptionDetails: {
            AmiSource: {
              AmiId: $ami,
              AccessRoleArn: $role,
              UserName: "ubuntu",
              OperatingSystemName: "UBUNTU",
              OperatingSystemVersion: $ubuntu
            },
            UsageInstructions: "The hatchrun scaler launches this AMI as an ephemeral GitHub Actions runner; it does nothing on its own. Setup: https://github.com/hatchrun/hatchrun#readme",
            RecommendedInstanceType: $instance_type,
            SecurityGroups: []
          }
        }
      }]
    }
  }]')

aws marketplace-catalog start-change-set \
  --region us-east-1 \
  --catalog AWSMarketplace \
  --intent "${intent}" \
  --change-set-name "hatchrun-${arch}-${IMAGE_VERSION}" \
  --change-set "${change_set}" \
  --query ChangeSetId --output text
