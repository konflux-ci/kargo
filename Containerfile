# Containerfile for Konflux build of Kargo

# Build arguments
ARG KARGO_VERSION

####################################################################################################
# ui-builder
####################################################################################################
FROM registry.access.redhat.com/ubi10/nodejs-24@sha256:5e5c444ef10c8952b6f9be839d0b47e147761f894593682344ebe64efa0d6aed AS ui-builder

ARG PNPM_VERSION=11.13.0
RUN npm install --global /cachi2/output/deps/generic/pnpm-${PNPM_VERSION}.tgz

WORKDIR /ui
# Hermeto injects .npmrc (file:// registry) for rewritten lockfile tarball names
COPY kargo/ui/package.json kargo/ui/pnpm-lock.yaml kargo/ui/pnpm-workspace.yaml kargo/ui/.npmrc ./

RUN pnpm install
COPY kargo/ui .

ARG KARGO_VERSION
RUN NODE_ENV='production' VERSION=${KARGO_VERSION} pnpm run build

####################################################################################################
# back-end-builder
####################################################################################################
FROM registry.access.redhat.com/ubi10/go-toolset@sha256:1f675b8824165404cbea41068342f9f8f6d47bfeccd6020bf8f9842876623d5b AS back-end-builder

ARG KARGO_VERSION
ARG CGO_ENABLED=0

ENV GOTOOLCHAIN=local

WORKDIR /kargo

# Copy Go module manifests first for layer caching (multi-module workspace)
COPY kargo/api/go.mod kargo/api/go.sum api/
COPY kargo/pkg/x/client/generated/go.mod pkg/x/client/generated/
COPY kargo/go.mod kargo/go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY kargo/api/ api/
COPY kargo/pkg/ pkg/
COPY kargo/cmd/ cmd/
COPY --from=ui-builder /ui/build pkg/server/ui/

USER 0

# Build credential-helper
RUN go build \
      -trimpath \
      -ldflags "-w -s" \
      -o bin/credential-helper \
      ./cmd/credential-helper

# Build main controlplane binary
ARG VERSION_PACKAGE=github.com/akuity/kargo/pkg/x/version
ARG GIT_COMMIT
ARG GIT_TREE_STATE
RUN go build \
      -trimpath \
      -ldflags "-w -X ${VERSION_PACKAGE}.version=${KARGO_VERSION} -X ${VERSION_PACKAGE}.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ') -X ${VERSION_PACKAGE}.gitCommit=${GIT_COMMIT} -X ${VERSION_PACKAGE}.gitTreeState=${GIT_TREE_STATE}" \
      -o bin/kargo \
      ./cmd/controlplane

####################################################################################################
# tools
# Prefetched via Hermeto generic artifacts (see artifacts.lock.yaml).
# go-toolset provides tar for unpacking Helm archives without microdnf/curl.
####################################################################################################
FROM registry.access.redhat.com/ubi10/go-toolset@sha256:1f675b8824165404cbea41068342f9f8f6d47bfeccd6020bf8f9842876623d5b AS tools

ARG TARGETOS=linux
ARG TARGETARCH=amd64

USER 0
WORKDIR /tools

# Normalize to artifact naming (Go arch). Fail loud if prefetch missing.
RUN case "${TARGETARCH}" in \
      amd64|x86_64) arch=amd64 ;; \
      arm64|aarch64) arch=arm64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    grpc="/cachi2/output/deps/generic/grpc_health_probe-${TARGETOS}-${arch}" && \
    helm_tgz="/cachi2/output/deps/generic/helm-${TARGETOS}-${arch}.tar.gz" && \
    test -f "${grpc}" && test -f "${helm_tgz}" && \
    cp "${grpc}" /tools/grpc_health_probe && \
    tar -xzf "${helm_tgz}" -C /tmp && \
    cp "/tmp/${TARGETOS}-${arch}/helm" /tools/helm && \
    chmod +x /tools/grpc_health_probe /tools/helm

####################################################################################################
# final
####################################################################################################
FROM registry.access.redhat.com/ubi10/ubi-minimal@sha256:e6c7c01447dc8eadf2a673e65fb6c607f16e168fe29a776fb937004f33c81cc0 AS final

ARG KARGO_VERSION
ARG TARGETARCH=amd64

# Versions pinned by Hermeto via rpms.lock.yaml (prefetch), not Containerfile.
# hadolint ignore=DL3041
RUN microdnf install -y ca-certificates git-core gnupg2 openssh-clients && \
    microdnf clean all

COPY --from=back-end-builder /kargo/bin/ /usr/local/bin/
COPY --from=tools /tools/ /usr/local/bin/
RUN case "${TARGETARCH}" in \
      amd64|x86_64) arch=amd64 ;; \
      arm64|aarch64) arch=arm64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    tini="/cachi2/output/deps/generic/tini-static-${arch}" && \
    test -f "${tini}" && \
    cp "${tini}" /sbin/tini && \
    chmod +x /sbin/tini

LABEL org.opencontainers.image.licenses=Apache-2.0 \
    org.opencontainers.image.description="Kargo is a Kubernetes-native continuous promotion platform for GitOps workflows." \
    org.opencontainers.image.documentation=https://kargo.io/ \
    org.opencontainers.image.source=https://github.com/akuity/kargo \
    org.opencontainers.image.title=kargo \
    org.opencontainers.image.vendor=Konflux \
    org.opencontainers.image.version=${KARGO_VERSION} \
    com.redhat.component=kargo \
    description="Kargo is a Kubernetes-native continuous promotion platform for GitOps workflows." \
    distribution-scope=public \
    io.k8s.description="Kargo is a Kubernetes-native continuous promotion platform for GitOps workflows." \
    name=kargo \
    release=${KARGO_VERSION} \
    url=https://github.com/akuity/kargo \
    vendor="Red Hat, Inc." \
    version=${KARGO_VERSION} \
    maintainer="Konflux DevProd Team <konflux-devprod@redhat.com>"

USER 65532:65532

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/kargo"]
