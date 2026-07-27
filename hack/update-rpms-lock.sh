#!/usr/bin/env bash
# Regenerate rpms.lock.yaml for Hermeto RPM prefetch.
# Requires podman. Run from repo root after changing final-stage packages or UBI digests.
#
# Repo IDs in ubi.repo must match Conforma known_rpm_repositories (RHSM-style):
#   https://github.com/release-engineering/rhtap-ec-policy/blob/main/data/known_rpm_repositories.yml
# Short ids from the UBI image (ubi-10-baseos-rpms) fail rpm_repos.ids_known.
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

# Prefer FROM ... AS final; fall back to last ubi-minimal FROM.
UBI_REF="$(awk '
  /^FROM / && / AS final$/ { print $2; found=1; exit }
  /^FROM / && /ubi-minimal/ { ref=$2 }
  END { if (!found && ref != "") print ref }
' Containerfile)"
if [[ -z "${UBI_REF}" ]]; then
  echo "Could not find final-stage ubi-minimal image in Containerfile" >&2
  exit 1
fi

echo "Refreshing ubi.repo from ${UBI_REF} (rewriting section ids for Conforma)..."
podman run --rm "${UBI_REF}" cat /etc/yum.repos.d/ubi.repo >ubi.repo.tmp

# Map short image repo ids → RHSM-style ids Conforma allows; enable source repos for SBOM.
# Use sed (not awk) so $basearch is literal.
sed -E \
  -e 's/^\[ubi-10-baseos-/[ubi-10-for-$basearch-baseos-/' \
  -e 's/^\[ubi-10-appstream-/[ubi-10-for-$basearch-appstream-/' \
  -e 's/^\[ubi-10-codeready-builder-/[codeready-builder-for-ubi-10-$basearch-/' \
  ubi.repo.tmp \
| awk '
    /^\[.*source-rpms\]/ { in_src=1 }
    /^\[/ && !/source-rpms/ { in_src=0 }
    in_src && /^enabled = 0$/ { print "enabled = 1"; next }
    { print }
  ' >ubi.repo
rm -f ubi.repo.tmp

{
  echo '# Repo IDs rewritten to Conforma known_rpm_repositories (RHSM-style).'
  echo '# See: https://github.com/release-engineering/rhtap-ec-policy/blob/main/data/known_rpm_repositories.yml'
  cat ubi.repo
} >ubi.repo.withhdr
mv ubi.repo.withhdr ubi.repo

echo "Resolving rpms.lock.yaml..."
podman run --rm \
  -v "${ROOT}:/work:Z" \
  -w /work \
  "${IMAGE}" \
  --outfile=rpms.lock.yaml \
  --image "${UBI_REF}" \
  rpms.in.yaml

echo "Wrote ${ROOT}/rpms.lock.yaml"
