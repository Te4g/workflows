# `deploy-coolify`

Callable path:

```text
Te4g/workflows/.github/workflows/deploy-coolify.yml@ref
```

## Purpose

Deploy a Coolify `Service` from a repository-owned Docker Compose file.

The workflow:

- checks out the caller repository
- reads the Compose file path you pass in
- updates `docker_compose_raw` for the target Coolify service
- optionally bulk updates service environment variables
- triggers deployment and can wait for completion

## Inputs

- `coolify-url`
  - Coolify base URL without `/api/v1`
- `service-uuid`
  - Coolify service UUID
- `compose-file`
  - path to the repo-owned Compose file
- `env-json`
  - optional JSON object or JSON array for service env updates
  - default: `""`
- `force-rebuild`
  - optional boolean
  - default: `false`
- `wait-for-completion`
  - optional boolean
  - default: `true`
- `timeout-seconds`
  - optional number
  - default: `900`
- `poll-interval-seconds`
  - optional number
  - default: `5`

## Secrets

- `coolify-token`

## Outputs

- `deployment_uuid`
- `deployment_url`

## Example Files

- [staging.example.yml](staging.example.yml)
- [release-production.example.yml](release-production.example.yml)

## Notes

- `env-json` accepts either:
  - a JSON object of key/value pairs
  - a JSON array of full Coolify env objects such as `key`, `value`, `is_literal`, or `is_multiline`
- the referenced Compose file should be production-safe
- the Coolify host must already be able to pull any private images referenced by the stack
