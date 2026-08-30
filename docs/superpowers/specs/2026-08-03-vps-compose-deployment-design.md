# VPS Compose Deployment Workflow Design

## Goal

Add a reusable GitHub Actions workflow that deploys a release-tagged Docker
Compose stack to a VPS after the existing GHCR build workflow succeeds.

The application repository owns a root `compose.prod.yaml`. Deployment copies
only that file to the VPS, authenticates the VPS to GHCR for the duration of the
image pull, starts the stack with the image tag published by the build job, and
only succeeds when every active container reports healthy.

## Architecture

Build and deployment remain separate reusable workflows:

- `.github/workflows/docker-build-publish-ghcr.yml` builds and publishes the
  release image.
- `.github/workflows/deploy-vps-compose.yml` deploys a repository-owned Compose
  file to a VPS.
- An application-owned release workflow calls both jobs and declares
  `needs: build` on the deployment job.

This preserves independent permissions and reuse while ensuring deployment
cannot begin when image publication fails. A separate `workflow_run` trigger is
not used because it would make release context and image output handoff less
direct.

The existing `.github/workflows/deploy.yml` remains the documented legacy
artifact and `rsync` deployment path. Its interface and behavior do not change.

## Reusable Workflow Interface

Callable path:

```text
Te4g/workflows/.github/workflows/deploy-vps-compose.yml@ref
```

### Inputs

- `image-tag`
  - required string
  - immutable image tag emitted as `needs.build.outputs.image_tag`
- `application-image-prefix`
  - required string
  - lowercase GHCR repository prefix emitted as `needs.build.outputs.image_name`
  - every resolved image beginning with this prefix must end exactly with
    `:<image-tag>`; at least one resolved image must match
- `source-ref`
  - optional string
  - caller repository Git ref containing `compose.prod.yaml`
  - defaults to the triggering commit; manual redeployments pass the existing
    release tag so the image and Compose contract come from the same release
- `deploy-path`
  - optional string
  - when empty, the workflow uses `/srv/compose/<repository-name>`
- `health-timeout-seconds`
  - optional number
  - default: `300`
  - must be an integer from `1` through `3600`
  - maximum time passed to Compose while waiting for the stack to become
    running and healthy

### Secrets

- `DEPLOY_HOST`
  - required VPS hostname or IP address
- `DEPLOY_PORT`
  - optional SSH port
  - defaults to `22` when empty
- `DEPLOY_USER`
  - required SSH user
- `DEPLOY_KEY`
  - required private SSH key
- `DEPLOY_KNOWN_HOSTS`
  - required OpenSSH `known_hosts` content for the selected host and port
- `GHCR_USERNAME`
  - required GHCR account name associated with the token
- `GHCR_TOKEN`
  - required token with read access to the deployed packages

### Outputs

The workflow has no callable outputs. It writes the deployed image tag,
destination, and final container states to the GitHub Actions job summary.

## Caller Release Workflow

The application repository owns the release trigger and passes the exact output
of the successful build job to deployment:

```yaml
name: Release production

on:
  release:
    types:
      - published

jobs:
  build:
    permissions:
      contents: read
      packages: write
    uses: Te4g/workflows/.github/workflows/docker-build-publish-ghcr.yml@main
    with:
      image-name: ghcr.io/${{ github.repository_owner }}/my-app
      image-tag: ${{ github.event.release.tag_name }}

  deploy:
    needs: build
    permissions:
      contents: read
    uses: Te4g/workflows/.github/workflows/deploy-vps-compose.yml@main
    with:
      image-tag: ${{ needs.build.outputs.image_tag }}
      application-image-prefix: ${{ needs.build.outputs.image_name }}
      deploy-path: /srv/compose/my-app
      health-timeout-seconds: 300
    secrets:
      DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
      DEPLOY_PORT: ${{ secrets.DEPLOY_PORT }}
      DEPLOY_USER: ${{ secrets.DEPLOY_USER }}
      DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
      DEPLOY_KNOWN_HOSTS: ${{ secrets.DEPLOY_KNOWN_HOSTS }}
      GHCR_USERNAME: ${{ secrets.GHCR_USERNAME }}
      GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }}
```

## Application Compose Contract

The caller repository must contain a non-empty `/compose.prod.yaml`. The file
must use the required `:${IMAGE_TAG:?…}` interpolation form for every
application image whose reference begins with `application-image-prefix`:

```yaml
services:
  app:
    image: ghcr.io/my-org/my-app:${IMAGE_TAG:?IMAGE_TAG is required}
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
```

Every persistent service started by the production stack must define a working
health check, either in its image or in `compose.prod.yaml`. A container that
does not expose Docker health state does not satisfy this deployment contract.
One-shot migration or initialization jobs are outside this workflow's health
contract and must run separately or behind a Compose profile that is not active
during the production deployment.

The prefix selects application images only. Fixed infrastructure images, such
as `postgres:16` or `redis:7`, are allowed when they do not begin with the
application image prefix. The resolved Compose stack must contain at least one
image matching the prefix, and every matching image must end in the requested
release tag. Optional `${IMAGE_TAG}` interpolation and hard-coded current
release tags do not meet the application image contract.

Compose interpolation happens at command execution time. The workflow does not
rewrite the Compose file. It atomically persists the selected release as the
only active `IMAGE_TAG=` entry in `<deploy-path>/.env`, preserving every other
entry and restricting the resulting file to mode `0600`. This keeps later bare
Compose operations pinned to the deployed release.

Because no other repository content is copied, relative `env_file`, config,
secret, or bind-mount sources must already exist under the deployment directory
on the VPS. External networks and volumes must also be provisioned when Compose
does not create them.

## Deployment Flow

1. Check out the caller repository at `source-ref`, or at the triggering commit
   when that input is omitted.
2. Validate that `compose.prod.yaml` exists, is non-empty, and that every
   application image selected by `application-image-prefix` uses the required
   `:${IMAGE_TAG:?…}` interpolation form.
3. Validate `image-tag` against Docker tag syntax and
   `application-image-prefix` as a lowercase GHCR repository path. Reject
   empty values, shell metacharacters, slashes in the tag, tags longer than 128
   characters, and unsafe prefixes.
4. Resolve the deployment path and require a normalized absolute path without
   whitespace, shell metacharacters, or `..` path segments.
5. Require the health timeout to be an integer from `1` through `3600`, require
   the SSH port to be an integer from `1` through `65535`, and reject newline or
   shell-control characters in SSH addressing values.
6. Configure the private key and pinned `known_hosts` data on the runner.
7. Verify SSH connectivity and verify that the remote user can run Docker and
   Docker Compose v2 without interactive `sudo`.
8. Create the deployment directory and upload only `compose.prod.yaml` under a
   run-specific temporary filename.
9. On the VPS, resolve the temporary file with `IMAGE_TAG=<image-tag>`, run
   `docker compose config --quiet`, and inspect `config --images`. Fail if
   no resolved image begins with `application-image-prefix`, or if any
   matching application image does not end in the supplied tag. This prevents a
   comment, unrelated environment value, or fixed infrastructure image from
   satisfying the raw `${IMAGE_TAG` text check.
10. Create a temporary remote Docker configuration, authenticate to `ghcr.io`
   with `docker login --password-stdin`, and pull every image in the resolved
   stack. Delete the temporary Docker configuration on exit.
11. Atomically rename the validated temporary Compose file to
    `<deploy-path>/compose.prod.yaml`.
12. Reject a symlink or non-regular `<deploy-path>/.env`, then atomically create
    or update its single `IMAGE_TAG=<image-tag>` entry without changing other
    environment values. Restrict the resulting file to mode `0600`.
13. Start the stack and wait for it:

    ```text
    docker compose -f compose.prod.yaml up --detach --remove-orphans --wait --wait-timeout <health-timeout-seconds>
    ```

14. Inspect every active container. Require it to be running, require Docker
    health state to exist, and require its health status to equal `healthy`.
15. Write the deployed tag, destination, Compose service status, and individual
    container health states to the job summary.

Deployments targeting the same caller repository are serialized even when
`deploy-path` differs. The workflow uses this conservative GitHub Actions
concurrency boundary with `cancel-in-progress: false` so an omitted path and
its explicitly supplied default can never deploy concurrently.

## Security

- SSH always uses strict host-key verification backed by
  `DEPLOY_KNOWN_HOSTS`. The workflow never uses
  `StrictHostKeyChecking=no`.
- The GHCR token is passed to `docker login` through standard input and is never
  included in command arguments or summaries.
- GHCR credentials use a temporary remote Docker configuration that is removed
  after the pull, including on failure.
- The GHCR token needs package read access only.
- Values interpolated into remote commands, including the application image
  prefix, are validated and shell-quoted.
- The runner's SSH key material exists only for the lifetime of the job.
- The deployment user must have narrowly scoped SSH access and non-interactive
  permission to manage this Docker host.

For a non-default SSH port, `DEPLOY_KNOWN_HOSTS` must contain the bracketed host
and port form expected by OpenSSH, such as `[vps.example.com]:2222`.

## Failure Behavior

Failures before `docker compose up` do not recreate the running stack. In
particular, authentication, interpolation, and image-pull failures leave current
containers running.

If Compose times out, a container is unhealthy, or a container lacks a health
check, the deployment job fails and reports current Compose and container
states. It does not print application logs automatically because those logs may
contain sensitive data.

The workflow does not perform automatic rollback. Compose may already have
recreated part of the stack when startup or health validation fails, and an
automatic rollback could compound application or database failures. The
operator rolls back explicitly by redeploying the preceding release tag.

## Verification Strategy

Implementation verification covers:

- workflow YAML syntax and reusable workflow structure;
- the exact input, secret, and default-value contract;
- a valid root Compose file and release tag path;
- rejection of a missing or empty Compose file;
- rejection of optional, missing, or hard-coded `IMAGE_TAG` application image
  references;
- acceptance of a tagged application image plus fixed Postgres infrastructure;
- rejection when no resolved image matches `application-image-prefix`;
- rejection when a matching application image uses `:latest` instead of the
  requested tag;
- rejection of invalid image tags and unsafe deployment paths;
- rejection of invalid health timeouts, SSH ports, and SSH addressing values;
- strict SSH host verification;
- GHCR password delivery through standard input and temporary credential
  cleanup;
- command ordering: validate, authenticate, pull, atomically install the
  Compose file, start, wait, inspect, summarize;
- atomic rename failure stops before `docker compose up`;
- failed health validation for unhealthy containers and containers without a
  Docker health check;
- the release example's `needs: build` dependency and use of
  `needs.build.outputs.image_tag`.

The checks remain local and deterministic. SSH and SCP stubs execute the
generated remote shell commands in a temporary absolute deployment directory
against a fake Docker/Compose command, rather than connecting to a real VPS. A
live deployment remains a separate integration validation using a test VPS and
test package.

## Documentation Changes

Adding `.github/workflows/deploy-vps-compose.yml` requires the same change to
include:

- an entry in the root `README.md` with its name, callable path, summary, and
  documentation link;
- `docs/deploy-vps-compose/README.md` documenting purpose, inputs, secrets,
  outputs, host requirements, Compose requirements, health behavior, and
  rollback behavior;
- `docs/deploy-vps-compose/release.example.yml` containing the complete build
  then deploy release workflow.

The legacy status of `deploy.yml` remains explicit in both the root and
per-workflow documentation.

## References

- [Docker Compose `up`](https://docs.docker.com/reference/cli/docker/compose/up/)
- [Compose service health checks](https://docs.docker.com/reference/compose-file/services/#healthcheck)
- [Control startup order with health checks](https://docs.docker.com/compose/how-tos/startup-order/)
