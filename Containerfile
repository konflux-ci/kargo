# Containerfile for Konflux build of Kargo

# Build arguments
ARG KARGO_VERSION

####################################################################################################
# ui-builder
####################################################################################################
FROM registry.access.redhat.com/ubi10/nodejs-22@sha256:b787df2d614ce4e950fdd0950805a3e23046158f47a76cda1c417a21987f02e3 AS ui-builder

ARG PNPM_VERSION=9.0.3
RUN npm install --global /cachi2/output/deps/generic/pnpm-${PNPM_VERSION}.tgz

WORKDIR /ui
COPY kargo/ui/package.json kargo/ui/pnpm-lock.yaml ./

RUN pnpm install --frozen-lockfile
COPY kargo/ui .

ARG KARGO_VERSION
RUN NODE_ENV='production' VERSION=${KARGO_VERSION} pnpm run build

####################################################################################################
# back-end-builder
####################################################################################################
FROM registry.access.redhat.com/ubi10/go-toolset@sha256:473a1b6bf2af9abb7b922732eadc2b48a455c8a281950fcb9fbd75bd326e7c24 AS back-end-builder

ARG KARGO_VERSION
ARG CGO_ENABLED=0

ENV GOTOOLCHAIN=local

WORKDIR /kargo

# Copy Go module manifests first for layer caching (multi-module workspace)
COPY kargo/api/go.mod kargo/api/go.sum api/
COPY kargo/pkg/client/generated/go.mod kargo/pkg/client/generated/go.sum pkg/client/generated/
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
RUN go build \
      -trimpath \
      -ldflags "-w -X ${VERSION_PACKAGE}.version=${KARGO_VERSION} -X ${VERSION_PACKAGE}.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
      -o bin/kargo \
      ./cmd/controlplane

####################################################################################################
# tools
####################################################################################################
FROM registry.access.redhat.com/ubi10/ubi-minimal@sha256:39c5de8723ad21c6a34e15cfba75f096d6a7191de98481b870b3dba575d65302 AS tools

ARG TARGETOS=linux
ARG TARGETARCH=amd64

WORKDIR /tools

RUN microdnf install -y tar-1.35 gzip-1.13 && \
    microdnf clean all

ARG GRPC_HEALTH_PROBE_VERSION=v0.4.50
RUN curl -fL -o /tools/grpc_health_probe \
      https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/grpc_health_probe-${TARGETOS}-${TARGETARCH} && \
    chmod +x /tools/grpc_health_probe

ARG HELM_VERSION=v3.21.0
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fL -o /tmp/helm.tar.gz \
      https://get.helm.sh/helm-${HELM_VERSION}-${TARGETOS}-${TARGETARCH}.tar.gz && \
    curl -fL -o /tmp/helm.tar.gz.sha256sum \
      https://get.helm.sh/helm-${HELM_VERSION}-${TARGETOS}-${TARGETARCH}.tar.gz.sha256sum && \
    echo "$(awk '{print $1}' /tmp/helm.tar.gz.sha256sum)  /tmp/helm.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/helm.tar.gz -C /tmp && \
    mv /tmp/${TARGETOS}-${TARGETARCH}/helm /tools/helm && \
    chmod +x /tools/helm

####################################################################################################
# final
####################################################################################################
FROM registry.access.redhat.com/ubi10/ubi-minimal@sha256:39c5de8723ad21c6a34e15cfba75f096d6a7191de98481b870b3dba575d65302

ARG KARGO_VERSION

RUN microdnf install -y ca-certificates-2025.2.80_v9.0.305 git-core-2.52.0 gnupg2-2.4.5 openssh-clients-9.9p1 && \
    microdnf clean all

COPY --from=back-end-builder /kargo/bin/ /usr/local/bin/
COPY --from=tools /tools/ /usr/local/bin/

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

ENTRYPOINT ["/usr/local/bin/kargo"]
