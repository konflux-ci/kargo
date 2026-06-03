# kargo (Konflux Build)

Konflux wrapper repo for the upstream [Kargo](https://github.com/akuity/kargo). The actual Go source lives in the `kargo/` git submodule — this repo owns only the build configuration and CI plumbing.

## Build & Verify Commands

| Action | Command |
|---|---|
| Init submodule | `git submodule update --init --recursive` |
| Build image | `podman build -f Containerfile -t kargo .` |
| Lint YAML | `yamllint <file>` |
| Lint Containerfile | `hadolint Containerfile` |
| Build upstream Go | `cd kargo && make build-cli` |
| Test upstream Go | `cd kargo && make test-unit` |

### Single-File Verification
- YAML: `yamllint path/to/file.yaml`
- Containerfile: `hadolint Containerfile`
- Shell scripts: `shellcheck path/to/script.sh`

## Project Layout
- `Containerfile` — multi-stage build (UBI10 Go toolset + Node.js for UI → UBI10 minimal)
- `kargo/` — git submodule tracking upstream tags (currently `main`)
- `.tekton/` — Konflux pipeline definitions (pull-request, push, pipeline)
- `.github/workflows/` — CI linting (hadolint, yamllint), auto-merge, dependency triage, release tagging
- `hack/` — helper scripts for submodule updates and release tagging
- `renovate.json` — MintMaker/Renovate config for automated submodule and image updates
- `CODEOWNERS` — PR approval routing

## Key Conventions
- The submodule tracks `main` on this branch. On release branches it will track tags.
- Renovate auto-creates PRs when new semver tags appear upstream.
- Container builds are handled by Konflux Tekton pipelines, not GitHub Actions.
- The Containerfile uses `GOTOOLCHAIN=local` to handle minor Go version mismatches.
- Runtime image runs as non-root (UID 65532) and includes git, gpg, openssh (required by Kargo at runtime).
- The image includes Helm and grpc_health_probe as runtime tools.
