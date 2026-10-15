#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

# Exchanges the job's GitHub OIDC token for credentials of ROLE_ARN and
# exports them to the rest of the job. Every value is masked first, the
# account id included, because the logs of this repository are public.
#
# Usage: ROLE_ARN=... assume-role.sh SESSION_NAME
#
# The credentials last DURATION_SECONDS (default 4 hours), which the
# role's MaxSessionDuration must allow.

set -euo pipefail

session=$1
: "${ROLE_ARN:?}" "${ACTIONS_ID_TOKEN_REQUEST_URL:?}" "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?}"

echo "::add-mask::$(cut -d: -f5 <<<"${ROLE_ARN}")"
token=$(curl -sSf -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" | jq -r .value)
echo "::add-mask::${token}"

credentials=$(aws sts assume-role-with-web-identity \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "${session}" \
  --web-identity-token "${token}" \
  --duration-seconds "${DURATION_SECONDS:-14400}" \
  --query Credentials --output json)
for key in AccessKeyId SecretAccessKey SessionToken; do
  echo "::add-mask::$(jq -r ".${key}" <<<"${credentials}")"
done
{
  echo "AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"${credentials}")"
  echo "AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"${credentials}")"
  echo "AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"${credentials}")"
} >> "${GITHUB_ENV}"
