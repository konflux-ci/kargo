#!/usr/bin/env bash
# Regenerate artifacts.lock.yaml for Hermeto generic prefetch.
# Run from repo root after bumping PNPM / Helm / grpc_health_probe / tini versions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/artifacts.lock.yaml"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

PNPM_VERSION="${PNPM_VERSION:-11.13.0}"
HELM_VERSION="${HELM_VERSION:-v3.21.2}"
GRPC_HEALTH_PROBE_VERSION="${GRPC_HEALTH_PROBE_VERSION:-v0.4.50}"
TINI_VERSION="${TINI_VERSION:-v0.19.0}"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

add_artifact() {
  local url="$1" filename="$2" file="$3"
  local sum
  sum="$(sha256_file "${file}")"
  ARTIFACTS+=("${url}|${filename}|${sum}")
}

ARTIFACTS=()

echo "Fetching pnpm ${PNPM_VERSION}..."
curl -fsSL -o "${WORKDIR}/pnpm-${PNPM_VERSION}.tgz" \
  "https://registry.npmjs.org/pnpm/-/pnpm-${PNPM_VERSION}.tgz"
add_artifact \
  "https://registry.npmjs.org/pnpm/-/pnpm-${PNPM_VERSION}.tgz" \
  "pnpm-${PNPM_VERSION}.tgz" \
  "${WORKDIR}/pnpm-${PNPM_VERSION}.tgz"

for arch in amd64 arm64; do
  echo "Fetching grpc_health_probe ${GRPC_HEALTH_PROBE_VERSION} (${arch})..."
  name="grpc_health_probe-linux-${arch}"
  curl -fsSL -o "${WORKDIR}/${name}" \
    "https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/${name}"
  add_artifact \
    "https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/${name}" \
    "${name}" \
    "${WORKDIR}/${name}"
done

for arch in amd64 arm64; do
  echo "Fetching Helm ${HELM_VERSION} (${arch})..."
  # Upstream only ships archives; store the tarball and extract at build time
  # (tools stage uses a base image that already provides tar).
  tarname="helm-${HELM_VERSION}-linux-${arch}.tar.gz"
  curl -fsSL -o "${WORKDIR}/${tarname}" "https://get.helm.sh/${tarname}"
  curl -fsSL -o "${WORKDIR}/${tarname}.sha256sum" "https://get.helm.sh/${tarname}.sha256sum"
  expected="$(awk '{print $1}' "${WORKDIR}/${tarname}.sha256sum")"
  actual="$(sha256_file "${WORKDIR}/${tarname}")"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "Helm checksum mismatch for ${tarname}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
  # Sanity-check archive contains the helm binary
  tar -tzf "${WORKDIR}/${tarname}" | grep -q "linux-${arch}/helm"
  add_artifact \
    "https://get.helm.sh/${tarname}" \
    "helm-linux-${arch}.tar.gz" \
    "${WORKDIR}/${tarname}"
done

for arch in amd64 arm64; do
  echo "Fetching tini-static ${TINI_VERSION} (${arch})..."
  name="tini-static-${arch}"
  curl -fsSL -o "${WORKDIR}/${name}" \
    "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/${name}"
  add_artifact \
    "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/${name}" \
    "${name}" \
    "${WORKDIR}/${name}"
done

{
  echo '---'
  echo 'metadata:'
  echo '  version: "1.0"'
  echo 'artifacts:'
  for entry in "${ARTIFACTS[@]}"; do
    IFS='|' read -r url filename sum <<<"${entry}"
    echo "  - download_url: \"${url}\""
    echo "    checksum: \"sha256:${sum}\""
    echo "    filename: \"${filename}\""
  done
} >"${OUT}"

echo "Wrote ${OUT}"

# Keep Containerfile ARG PNPM_VERSION in sync with the lock filename.
CONTAINERFILE="${ROOT}/Containerfile"
if ! grep -qE '^ARG PNPM_VERSION=' "${CONTAINERFILE}"; then
  echo "Containerfile missing ARG PNPM_VERSION=..." >&2
  exit 1
fi
tmp="$(mktemp)"
sed -E "s/^ARG PNPM_VERSION=.*/ARG PNPM_VERSION=${PNPM_VERSION}/" \
  "${CONTAINERFILE}" >"${tmp}"
mv "${tmp}" "${CONTAINERFILE}"
echo "Updated Containerfile ARG PNPM_VERSION=${PNPM_VERSION}"
