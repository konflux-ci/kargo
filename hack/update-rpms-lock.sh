#!/usr/bin/env bash
# Regenerate rpms.lock.yaml for Hermeto RPM prefetch.
# Requires podman. Run from repo root after changing RPM packages or base-image digests.
#
# Repo IDs in hi.repo must match Conforma known_rpm_repositories:
#   https://github.com/release-engineering/rhtap-ec-policy/blob/main/data/known_rpm_repositories.yml
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

# RPMs are installed in the tools stage, not the final runtime stage.
RPM_STAGE="${RPM_LOCKFILE_STAGE:-tools}"
BASE_IMAGE="$(awk -v stage="${RPM_STAGE}" '
  $1 == "FROM" && $NF == stage { print $2; exit }
' Containerfile)"
if [[ -z "${BASE_IMAGE}" ]]; then
  echo "Could not find ${RPM_STAGE} stage image in Containerfile" >&2
  exit 1
fi

echo "Refreshing hi.repo from ${BASE_IMAGE}..."
podman run --rm "${BASE_IMAGE}" sh -c 'cat /etc/yum.repos.d/*.repo' >hi.repo.tmp

# Hummingbird repository IDs are already Conforma-approved. Enable source RPMs
# so the generated lock contains source packages for SBOM generation.
awk '
  /^\[.*source-rpms\]/ { in_src=1 }
  /^\[/ && !/source-rpms/ { in_src=0 }
  in_src && /^enabled[[:space:]]*=/ { print "enabled=1"; next }
  { print }
' hi.repo.tmp >hi.repo
rm -f hi.repo.tmp

{
  echo '# Repo IDs from the Hummingbird base image; all are Conforma known RPM repositories.'
  echo '# See: https://github.com/release-engineering/rhtap-ec-policy/blob/main/data/known_rpm_repositories.yml'
  cat hi.repo
} >hi.repo.withhdr
mv hi.repo.withhdr hi.repo

echo "Resolving rpms.lock.yaml..."
podman run --rm \
  -v "${ROOT}:/work:Z" \
  -w /work \
  "${IMAGE}" \
  --outfile=rpms.lock.yaml \
  --image "${BASE_IMAGE}" \
  rpms.in.yaml

echo "Wrote ${ROOT}/rpms.lock.yaml"
