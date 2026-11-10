#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-only

# Keeps the newest KEEP image versions per architecture in AWS_REGION,
# where the build makes its source AMIs, and deregisters the rest with
# their snapshots, which are what costs money. Only AMIs this account
# owns and tagged by the build are touched.
#
# The AMIs the previous release names are kept as well. A build that
# fails one architecture can leave an unreleased AMI newer than the
# previous release's AMI, and that release is the rollback target.
#
# Usage: KEEP=2 prune.sh
#
# Set DRY_RUN=1 to print what would be deregistered without doing it.
# When GH_TOKEN is unset, as in a local run, no release is protected.

set -euo pipefail

keep=${KEEP:-2}
dry_run=${DRY_RUN:-0}

# AMIs named by the release before this build's, which stays launchable
# if the newest release has to be rolled back.
previous_amis() {
  [ -n "${GH_TOKEN:-}" ] || return 0
  command -v gh >/dev/null || return 0
  local previous tmp
  tmp=$(mktemp)
  previous=$(gh release list --repo "${GITHUB_REPOSITORY}" --limit 2 \
    --json tagName --jq '.[1].tagName // empty' || true)
  if [ -n "${previous}" ] &&
    gh release download "${previous}" --repo "${GITHUB_REPOSITORY}" \
      --pattern manifest.json --output "${tmp}" --clobber 2>/dev/null &&
    [ -s "${tmp}" ]; then
    jq -r '.amis[][]' "${tmp}"
  fi
  rm -f "${tmp}"
}

protected=$(previous_amis)

for arch in amd64 arm64; do
  # Oldest first, so everything but the last KEEP lines goes.
  old=$(aws ec2 describe-images --owners self \
    --filters "Name=tag:hatchrun:arch,Values=${arch}" Name=tag-key,Values=hatchrun:image-version \
    --query 'sort_by(Images, &CreationDate)[].ImageId' --output text \
    | tr '\t' '\n' | sed '/^$/d' \
    | awk -v keep="${keep}" '{ ids[NR] = $0 } END { for (i = 1; i <= NR - keep; i++) print ids[i] }')
  for ami in ${old}; do
    if grep -qxF "${ami}" <<< "${protected}"; then
      echo "keeping ${ami}, the previous release names it" >&2
      continue
    fi
    echo "deregistering ${ami}" >&2
    [ "${dry_run}" = 1 ] && continue
    aws ec2 deregister-image --image-id "${ami}" --delete-associated-snapshots >/dev/null
  done
done
