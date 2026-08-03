# `deploy-vps-compose`

Callable path:

```text
Te4g/workflows/.github/workflows/deploy-vps-compose.yml@ref
```

## Purpose

Deploy a release-tagged, repository-owned Compose stack to a VPS. The workflow copies only the caller's root `compose.prod.yaml`, validates every application image selected by `application-image-prefix`, authenticates temporarily to GHCR, pulls the requested images, deploys the stack, waits, and validates that every reported container is `running|healthy`.

## Inputs

- `image-tag` (required)
  - Immutable Docker image tag to deploy. It must be 1-128 characters and use only `A-Z`, `a-z`, `0-9`, `_`, `.`, or `-`.
- `application-image-prefix` (required)
  - GHCR application image repository prefix. Every resolved image beginning with this prefix must end exactly with `:<image-tag>`, and at least one resolved image must match.
  - It must be a lowercase `ghcr.io/` repository path without a tag, whitespace, or shell metacharacters; for example `ghcr.io/example/app`.
- `deploy-path` (optional)
  - Absolute VPS deployment directory.
  - Default: `/srv/compose/<repository-name>`.
- `health-timeout-seconds` (optional)
  - Maximum time Docker Compose may wait for health.
  - Default: `300`; accepted range: integer `1` through `3600`.

## Secrets

- `DEPLOY_HOST` (required) — VPS hostname or IP address.
- `DEPLOY_PORT` (optional) — SSH port; defaults to `22`.
- `DEPLOY_USER` (required) — non-interactive SSH user.
- `DEPLOY_KEY` (required) — private key for the deployment user.
- `DEPLOY_KNOWN_HOSTS` (required) — pinned SSH known-hosts entries.
- `GHCR_USERNAME` (required) — GHCR account used to pull the image.
- `GHCR_TOKEN` (required) — GHCR token with `read:packages`.

For a non-default SSH port, `DEPLOY_KNOWN_HOSTS` must use bracketed host-and-port entries, for example `[vps.example.com]:2222 ssh-ed25519 ...`.

## Outputs

This workflow has no callable outputs. Its job summary records the deployed tag, remote path, and container health rows.

## Repository requirements

- The caller repository must have a non-empty root `compose.prod.yaml`.
- At least one application image reference must interpolate `IMAGE_TAG`, for example `image: ghcr.io/example/app:${IMAGE_TAG}`.
- Every resolved application image whose reference begins with `application-image-prefix` must end with the supplied release tag. Fixed infrastructure images such as `postgres:16` and `redis:7` are allowed when they do not match that prefix.
- Every persistent service must define a health check; the workflow requires each Compose row to be exactly `running|healthy`.
- One-shot jobs must run separately, or remain behind a profile that is inactive during production deployment.

## VPS requirements

- Docker Engine and Docker Compose v2 with `--wait` support.
- Non-interactive Docker access for `DEPLOY_USER`.
- A writable deployment directory.
- Any relative files and external resources needed by the Compose stack pre-provisioned on the VPS.

## Security and failure behavior

The workflow uses pinned known hosts and never disables SSH host verification. GHCR authentication uses a temporary remote Docker configuration that is deleted when the pull command exits; the token is passed over SSH standard input.

It validates the resolved application image tags before logging in, preserving the uploaded `compose.prod.yaml` on a health failure, and does not run `docker compose down` or attempt rollback. To roll back, invoke the workflow again with the previous image tag after confirming that tag is available.

## Example

- [release.example.yml](release.example.yml)
