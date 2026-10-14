#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

# Points hatchrun-cloud's images table at the AMIs of release
# ubuntu26-VERSION, or of the newest release when VERSION is empty, by
# posting its manifest.json with the job's GitHub OIDC token.
#
# The manifest must carry the provenance attestation that build.yml on
# main made for it, so an asset swapped into the release is refused
# here. hatchrun-cloud accepts tokens only from register.yml on main in
# the image-build environment, and refuses a release older than the one
# it holds.
#
# Usage: GH_TOKEN=... register.sh [VERSION]
#
# Set REGISTER_URL to post somewhere else, such as wrangler dev.

set -euo pipefail

version=${1:-}
url=${REGISTER_URL:-https://app.hatchrun.io/api/internal/images}
audience=https://app.hatchrun.io
: "${GITHUB_REPOSITORY:?}" "${ACTIONS_ID_TOKEN_REQUEST_URL:?}" "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?}"

if [ -n "${version}" ]; then
  tag="ubuntu26-${version}"
else
  tag=$(gh release list --repo "${GITHUB_REPOSITORY}" --exclude-drafts --limit 1 \
    --json tagName --jq '.[0].tagName')
fi
echo "registering ${tag}" >&2

dir=$(mktemp -d)
trap 'rm -rf "${dir}"' EXIT
gh release download "${tag}" --repo "${GITHUB_REPOSITORY}" --pattern manifest.json --dir "${dir}"
gh attestation verify "${dir}/manifest.json" --repo "${GITHUB_REPOSITORY}" \
  --signer-workflow "${GITHUB_REPOSITORY}/.github/workflows/build.yml" \
  --source-ref refs/heads/main >/dev/null
jq -e --arg version "${tag#ubuntu26-}" '.version == $version' "${dir}/manifest.json" >/dev/null \
  || { echo "::error::manifest.json of ${tag} names another version" >&2; exit 1; }

token=$(curl -sSf -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${audience}" | jq -r .value)
echo "::add-mask::${token}"

# curl retries timeouts and 5xx answers; a refusal fails at once.
curl -sS --fail-with-body --retry 3 \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" \
  --data-binary @"${dir}/manifest.json" \
  "${url}"
echo
