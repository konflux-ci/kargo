#!/usr/bin/env bash
# Regenerate rpms.lock.yaml for Hermeto RPM prefetch.
# Requires podman. Run from repo root after changing final-stage packages or UBI digests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

IMAGE="${RPM_LOCKFILE_IMAGE:-localhost/rpm-lockfile-prototype}"

if ! podman image exists "${IMAGE}"; then
  echo "Building ${IMAGE}..."
  curl -fsSL \
    https://raw.githubusercontent.com/konflux-ci/rpm-lockfile-prototype/refs/heads/main/Containerfile \
    | podman build -t "${IMAGE}" -
fi

# Refresh ubi.repo from the final-stage base digest when possible
UBI_REF="$(awk '
  /^FROM / && /ubi-minimal/ { ref=$2 }
  END { print ref }
' Containerfile)"
if [[ -n "${UBI_REF}" ]]; then
  echo "Refreshing ubi.repo from ${UBI_REF}..."
  podman run --rm "${UBI_REF}" cat /etc/yum.repos.d/ubi.repo >ubi.repo.tmp
  # Keep source repos enabled for complete SBOMs
  awk '
    /^\[.*source-rpms\]/ { in_src=1 }
    /^\[/ && !/source-rpms/ { in_src=0 }
    in_src && /^enabled = 0$/ { print "enabled = 1"; next }
    { print }
  ' ubi.repo.tmp >ubi.repo
  rm -f ubi.repo.tmp
fi

echo "Resolving rpms.lock.yaml..."
podman run --rm \
  -v "${ROOT}:/work:Z" \
  -w /work \
  "${IMAGE}" \
  --outfile=rpms.lock.yaml \
  --image "${UBI_REF}" \
  rpms.in.yaml

echo "Wrote ${ROOT}/rpms.lock.yaml"
