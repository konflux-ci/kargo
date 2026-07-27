# kargo (Konflux Build)

Konflux wrapper repo for the upstream [Kargo](https://github.com/akuity/kargo). The actual Go source lives in the `kargo/` git submodule — this repo owns only the build configuration and CI plumbing.

## Build & Verify Commands

| Action | Command |
|---|---|
| Init submodule | `git submodule update --init --recursive` |
| Build image | `podman build -f Containerfile -t kargo .` (needs Hermeto `/cachi2` for CI-parity) |
| Regenerate generic artifacts lock | `./hack/update-artifacts-lock.sh` |
| Regenerate RPM lock | `./hack/update-rpms-lock.sh` |
| Lint YAML | `yamllint <file>` |
| Lint Containerfile | `hadolint Containerfile` |
| Build upstream Go | `cd kargo && make build-cli` |
| Test upstream Go | `cd kargo && make test-unit` |

### Single-File Verification
- YAML: `yamllint path/to/file.yaml`
- Containerfile: `hadolint Containerfile`
- Shell scripts: `shellcheck path/to/script.sh`

## Project Layout
- `Containerfile` — multi-stage hermetic build (UBI10 Go toolset + Node.js for UI → UBI10 minimal)
- `kargo/` — git submodule tracking upstream tags (currently `main`)
- `artifacts.lock.yaml` — Hermeto generic prefetch (pnpm CLI, Helm, grpc_health_probe, tini)
- `rpms.in.yaml` / `rpms.lock.yaml` / `ubi.repo` — Hermeto RPM prefetch for the final image
- `.tekton/` — Konflux pipeline definitions (pull-request, push, pipeline); prefetch includes rpm; hermetic flip is a follow-up once CI validates offline paths
- `.github/workflows/` — CI linting (hadolint, yamllint), auto-merge, dependency triage, release tagging
- `hack/` — helper scripts for submodule updates, lockfile regeneration, and release tagging
- `renovate.json` — MintMaker/Renovate config for automated submodule and image updates
- `CODEOWNERS` — PR approval routing

## Hermetic build constraints

Konflux builds run with network isolation. Prefetch (gomod, pnpm, generic, rpm) must cover every dependency.

- Do **not** add `curl`, `wget`, or `git clone` in Containerfile `RUN` steps
- Do **not** add `microdnf`/`dnf` packages without updating `rpms.in.yaml` and running `./hack/update-rpms-lock.sh`
- After MintMaker UBI digest bumps, re-run `./hack/update-rpms-lock.sh`
- After bumping Helm / grpc_health_probe / tini / pnpm, re-run `./hack/update-artifacts-lock.sh`

## Key Conventions
- The submodule tracks `main` on this branch. On release branches it will track tags.
- Renovate auto-creates PRs when new semver tags appear upstream.
- Container builds are handled by Konflux Tekton pipelines, not GitHub Actions.
- The Containerfile uses `GOTOOLCHAIN=local` to handle minor Go version mismatches.
- Runtime image runs as non-root (UID 65532) and includes git, gpg, openssh (required by Kargo at runtime).
- The image includes Helm, grpc_health_probe, and tini as runtime tools.
