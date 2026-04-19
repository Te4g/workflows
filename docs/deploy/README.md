# `deploy`

Callable path:

```text
Te4g/workflows/.github/workflows/deploy.yml@ref
```

## Purpose

Legacy deployment workflow that:

- checks out the caller repository
- downloads the `build` artifact if it exists
- syncs the repository to a remote host with `rsync`
- runs `make install-prod` on the target host

## Inputs

- `artifact-path`
  - optional extraction path for the downloaded `build` artifact
  - default: `.`

## Secrets

- `DEPLOY_HOST`
- `DEPLOY_PORT`
- `DEPLOY_USER`
- `DEPLOY_KEY`

## Outputs

This workflow does not expose outputs.

## Repository Requirements

- a root `.rsyncignore`
- a root `Makefile`
- an `install-prod` target in that `Makefile`

## Example Files

- [push.example.yml](push.example.yml)

## Notes

- This is the legacy SSH-based deployment path.
- It disables strict host key checking during SSH and `rsync`.
- Prefer the Coolify workflow for Compose-based deployments when that matches your platform.
