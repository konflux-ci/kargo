# Containerfile for Konflux build of Kargo

# Build arguments
ARG KARGO_VERSION

####################################################################################################
# ui-builder
####################################################################################################
FROM registry.access.redhat.com/hi/nodejs:26@sha256:4d9a183b5b8809723eeada63cf775f8e976a3d26b7ef339e7dfd3152754c0bee AS ui-builder

ARG PNPM_VERSION=11.13.0
USER 0
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
FROM registry.access.redhat.com/hi/go:1.27@sha256:cf54e1f8345bd38401ca8b651b4b0db65c784c23d4ab2b03f97d08a1d8bbbde4 AS back-end-builder

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
# Use 'builder' version of core-runtime so 'dnf' is available for installing 'tar'.
####################################################################################################
FROM registry.access.redhat.com/hi/core-runtime:latest-builder@sha256:7b6b0d5eae0a26fc4dd44f368c0157d8e0672eb6bbb95e281d0bde30eb38070b AS tools

ARG TARGETOS=linux
ARG TARGETARCH=amd64

USER 0
WORKDIR /tools

# Version pinned by Hermeto via rpms.lock.yaml (prefetch), not Containerfile.
# hadolint ignore=DL3041
RUN dnf install -y tar gzip && \
    dnf clean all


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
FROM registry.access.redhat.com/hi/core-runtime:latest@sha256:58f9030ce520821c61798d41ca52aa2b10ba5f20c49245f63ecffcfcaa3d464f AS final

ARG KARGO_VERSION
ARG TARGETARCH=amd64

USER 0

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
