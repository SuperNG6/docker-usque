# Repository Guidelines

## Project Structure & Module Organization

This repository packages upstream `Diniboy1123/usque` as a Docker image.

- `Dockerfile` builds the upstream Go binary in a `golang:<version>-alpine` stage and copies it into Alpine.
- `docker-entrypoint.sh` maps `USQUE_*` environment variables to `usque` subcommands and handles first-run registration.
- `README.md` contains user-facing usage examples and environment variable documentation.
- `tests/` contains lightweight shell regression tests for entrypoint argument mapping.
- `.github/workflows/Build Image.yml` builds and pushes multi-arch `lite` and `tun` images to Docker Hub and GHCR.

There is no vendored application source tree; upstream source is cloned during Docker build.

## Build, Test, and Development Commands

- `docker build -t docker-usque:local --build-arg USQUE_REF=main .` builds the default lite image locally.
- `docker build -t docker-usque:tun --build-arg BUILD_VARIANT=tun --build-arg USQUE_REF=main .` builds the TUN-capable variant with `iproute2`.
- `docker run --rm docker-usque:local --help` verifies the image starts.
- `sh tests/entrypoint-l4-modes.sh` checks L4 proxy environment variable mapping.
- `sh -n docker-entrypoint.sh` checks shell syntax before committing entrypoint changes.

For CI changes, inspect the workflow with `gh run list` and `gh run view <run-id> --log` after pushing.

## Coding Style & Naming Conventions

Use POSIX `sh` in `docker-entrypoint.sh`; avoid Bash-only syntax. Keep indentation at two spaces in YAML and continued shell blocks where practical. User-facing environment variables must use the `USQUE_` prefix and be documented in `README.md`. Keep Docker build arguments uppercase, for example `USQUE_REF`, `GO_VERSION`, and `BUILD_VARIANT`.

## Testing Guidelines

There is no broad unit test suite. Validate shell changes with `sh -n docker-entrypoint.sh`, run relevant scripts in `tests/`, and build the affected Docker variant. For behavior changes, run a container with representative environment variables:

```bash
docker run --rm -e USQUE_MODE=socks -e USQUE_PORT=1080 docker-usque:local --help
```

For workflow edits, prefer a manual `workflow_dispatch` run before relying on the scheduled build.

## Commit & Pull Request Guidelines

Recent history uses short imperative messages and occasional Conventional Commit prefixes such as `feat:`, `fix:`, and `refactor:`. Example: `fix: handle nativetun persist flag`.

Pull requests should include a short summary, the affected files or behavior, validation commands run, and any image or workflow impact. Link related issues when available. For changes that affect published image behavior, update `README.md` in the same PR.

## Security & Configuration Tips

Do not commit WARP, Zero Trust, Docker Hub, or GHCR credentials. Keep runtime secrets in environment variables or GitHub Actions secrets. Avoid logging token values in shell scripts or workflows.
