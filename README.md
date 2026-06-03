# Kargo Konflux Build

Konflux wrapper repo for the upstream [Kargo](https://github.com/akuity/kargo). The actual Go source lives in the `kargo/` git submodule — this repo owns only the build configuration and CI plumbing.

## Overview

This repository acts as a mediator between **Konflux** and upstream **Kargo**. Custom Containerfiles enable **hermetic builds** within the Konflux environment using Red Hat UBI base images.

The produced image contains:
- **kargo** controlplane binary (API server, controller, management-controller, webhooks, garbage-collector)
- **credential-helper** for Git repository access
- **UI** (React/TypeScript frontend built with Vite)
- **helm** binary (required by the kustomize-build promotion step)
- **grpc_health_probe** for health checking

## Quick Start

1. **Initialize the submodule**:

   ```bash
   git submodule update --init --recursive
   ```

2. **Build locally**:

   ```bash
   podman build -f Containerfile -t kargo .
   ```

## Submodule Updates

MintMaker/Renovate automatically creates pull requests for submodule updates. The `deptriage` workflow performs LLM-powered impact analysis and auto-approves safe updates.

To manually update the submodule:

```bash
./hack/update_submodule.sh
```

Or directly:

```bash
cd kargo
git fetch --tags
git checkout <branch | tag-name>
cd ..
git add kargo
git commit -m "Update kargo submodule to <version>"
```

## Containerfile Features

- **Red Hat UBI10 base images**: Go Toolset for building, UBI Minimal for runtime
- **Pinned image versions**: SHA digests for reproducible builds
- **Multi-stage builds**: Separate stages for UI, Go backend, tools, and runtime
- **Hermetic builds**: CACHI2 Go module prefetch via Konflux pipelines
- **Layer caching**: Go module dependencies downloaded before source copy
- **Security**: Minimal runtime image, runs as non-root (UID 65532)
- **GOTOOLCHAIN=local**: Tolerates minor Go version mismatches between image and go.mod

## CI/CD

- **Konflux Tekton pipelines** (`.tekton/`): Multi-arch builds (x86_64 + arm64), security scans, trusted artifacts
- **GitHub Actions** (`.github/workflows/`): Containerfile/YAML linting, dependency triage, auto-merge
- **Release tagging** (`hack/kargo_tag.sh`): Automated on release branches

## Upstream Project

- [Kargo Documentation](https://kargo.io/)
- [Upstream Repository](https://github.com/akuity/kargo)

## License

Apache-2.0 (same as the upstream Kargo project).
