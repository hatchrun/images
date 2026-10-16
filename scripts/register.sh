#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

# Points hatchrun-cloud's images table at the AMIs of release
# ubuntu26-VERSION, or of the newest release when VERSION is empty, by
# posting its manifest.json with the job's GitHub OIDC token.
#
# The manifest must carry the provenance attestation that build.yml on
# main made for it on a GitHub-hosted runner, so an asset swapped into
# the release is refused here. hatchrun-cloud accepts tokens only from
# register.yml on main in the image-build environment, each token once,
# and refuses a release older than the one it holds.
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
  if ! [[ "${version}" =~ ^[0-9]{8}\.[0-9]{4}$ ]]; then
    echo "::error::version ${version} is not YYYYMMDD.HHMM" >&2
    exit 1
  fi
  tag="ubuntu26-${version}"
else
  tag=$(gh release list --repo "${GITHUB_REPOSITORY}" --exclude-drafts --limit 1 \
    --json tagName --jq '.[0].tagName')
fi
echo "registering ${tag}" >&2

dir=$(mktemp -d)
trap 'rm -rf "${dir}"' EXIT
gh release download "${tag}" --repo "${GITHUB_REPOSITORY}" --pattern manifest.json --dir "${dir}"
# The certificate names the signing workflow and its ref exactly.
gh attestation verify "${dir}/manifest.json" --repo "${GITHUB_REPOSITORY}" \
  --cert-identity "https://github.com/${GITHUB_REPOSITORY}/.github/workflows/build.yml@refs/heads/main" \
  --deny-self-hosted-runners >/dev/null
jq -e --arg version "${tag#ubuntu26-}" '.version == $version' "${dir}/manifest.json" >/dev/null \
  || { echo "::error::manifest.json of ${tag} names another version" >&2; exit 1; }

# Each token posts once, so every attempt asks for a new one. GitHub
# publishes a new signing key before it uses it, but hatchrun-cloud
# looks for an unknown key at most once a minute: a token signed with a
# key it has not seen yet is tried again after that.
post() {
  local token
  token=$(curl -sSf -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${audience}" | jq -r .value)
  echo "::add-mask::${token}"
  # curl retries timeouts and 5xx answers; a refusal comes back at once.
  curl -sS --retry 3 -o "${dir}/answer" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    --data-binary @"${dir}/manifest.json" \
    "${url}" >"${dir}/status"
}

post
if [ "$(cat "${dir}/status")" = 401 ] && grep -q '"no key with kid' "${dir}/answer"; then
  echo "hatchrun-cloud does not know the token's key yet; trying again in a minute" >&2
  sleep 61
  post
fi
status=$(cat "${dir}/status")
cat "${dir}/answer"
echo
if [[ "${status}" != 2?? ]]; then
  echo "::error::hatchrun-cloud answered ${status}" >&2
  exit 1
fi
