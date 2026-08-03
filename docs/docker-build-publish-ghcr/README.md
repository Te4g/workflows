# `docker-build-publish-ghcr`

Callable path:

```text
Te4g/workflows/.github/workflows/docker-build-publish-ghcr.yml@ref
```

## Purpose

Build a Docker image and publish it to GHCR.

The workflow emits the published image metadata so a later deploy job can reuse the exact image tag or digest.

## Inputs

- `image-name`
  - fully qualified image name
- `context`
  - optional Docker build context
  - default: `.`
- `dockerfile`
  - optional Dockerfile path
  - default: `./Dockerfile`
- `image-tag`
  - optional explicit image tag
  - default: `sha-<git-sha>`
- `target`
  - optional Docker build target
- `platforms`
  - optional platform list
  - default: `linux/amd64`
- `floating-tag`
  - optional additional tag such as `main` or `latest`
- `provenance`
  - optional boolean
  - default: `false`
- `sbom`
  - optional boolean
  - default: `false`

## Secrets

This workflow uses the caller workflow `GITHUB_TOKEN`. No explicit custom secret mapping is required.

The caller job should grant:

- `contents: read`
- `packages: write`

## Outputs

- `image_name`
- `image_tag`
- `image_ref`
- `image_digest`

## Example Files

- [push.example.yml](push.example.yml)
- [release.example.yml](release.example.yml)
- [Build, then deploy a release to a VPS](../deploy-vps-compose/release.example.yml)
  - calls this workflow first
  - passes its `image_name` and `image_tag` outputs to
    `deploy-vps-compose.yml` through a dependent `deploy` job

## Notes

- use `image-tag` when you want the published tag to match a GitHub release version
- use `target` for multi-stage Dockerfiles that expose multiple deployable images
