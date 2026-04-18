# AGENTS.md

This repository stores callable reusable GitHub Actions workflows.

## Documentation rule

Whenever you add, remove, rename, move, or modify a workflow file under:

- `.github/workflows/`

you must update:

- [README.md](/Users/teag/Dev/workflows/README.md)
- the matching docs directory under `/Users/teag/Dev/workflows/docs/<workflow-name>/`

in the same change.

## Documentation structure

For every callable workflow file:

1. The root README must contain:
   - the workflow name
   - the callable path
   - a short summary
   - a link to its docs directory
2. A matching docs directory must exist:
   - `docs/<workflow-basename-without-.yml>/`
3. That docs directory must contain:
   - `README.md`
   - at least one `*.example.yml` file

Examples:

- `.github/workflows/deploy.yml` -> `docs/deploy/`
- `.github/workflows/deploy-coolify.yml` -> `docs/deploy-coolify/`
- `.github/workflows/docker-build-publish-ghcr.yml` -> `docs/docker-build-publish-ghcr/`

## Per-workflow README requirements

Each `docs/<workflow>/README.md` must include:

1. The callable path.
2. A short purpose summary.
3. The public interface:
   - inputs
   - secrets
   - outputs if any
4. Notes or repository requirements when relevant.
5. Links to the example YAML files in that directory.

## GitHub reusable workflow constraint

GitHub reusable workflows must live in `.github/workflows/`.

## Maintenance expectations

- Keep examples aligned with the current workflow interface.
- Remove stale examples when inputs or secrets change.
- If a legacy workflow remains in the repo, label it as legacy in the README instead of silently treating it as the default path.
