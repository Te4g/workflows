# Reusable GitHub Actions Workflows

This repository exposes callable reusable workflows from [`.github/workflows/`](.github/workflows/).

Workflow-specific documentation lives under `docs/<workflow-name>/`.

## Available Workflows

- [`deploy`](docs/deploy/README.md)
  - Callable path: `Te4g/workflows/.github/workflows/deploy.yml@ref`
  - Legacy SSH + `rsync` deployment workflow.
- [`deploy-coolify`](docs/deploy-coolify/README.md)
  - Callable path: `Te4g/workflows/.github/workflows/deploy-coolify.yml@ref`
  - Coolify service deployment workflow for repo-owned Compose files.
- [`deploy-vps-compose`](docs/deploy-vps-compose/README.md)
  - Callable path: `Te4g/workflows/.github/workflows/deploy-vps-compose.yml@ref`
  - Secure VPS deployment of a release-tagged, repository-owned Compose stack with a persistent image tag and strict health validation.
- [`docker-build-publish-ghcr`](docs/docker-build-publish-ghcr/README.md)
  - Callable path: `Te4g/workflows/.github/workflows/docker-build-publish-ghcr.yml@ref`
  - GHCR build and publish workflow.

## Documentation Convention

For each callable workflow there is a matching docs directory:

- `docs/deploy/`
- `docs/deploy-coolify/`
- `docs/deploy-vps-compose/`
- `docs/docker-build-publish-ghcr/`

Each directory contains:

- `README.md`
  - purpose
  - callable path
  - inputs, secrets, outputs
  - notes and requirements
- one or more `.example.yml` files
  - concrete caller workflow examples

## GitHub Reference

Reusable workflows must live in `.github/workflows/` and are referenced as:

- `owner/repo/.github/workflows/file.yml@ref`

References:
- [Reuse workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows)
- [Reusable workflows reference](https://docs.github.com/en/actions/reference/workflows-and-actions/reusable-workflows)
