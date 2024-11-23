# Workflow templates

## [Deploy](.github/workflows/deploy.yml)

Repositories using the reusable workflow must do the following:
- Create a `.rsyncignore` file at the root of the repository
- Create a `Makefile` at the root of the repository with the following target:
    - `install-prod`: Install the project
- Create the following secrets in the repository (it can be done with the github CLI: `gh secret set DEPLOY_HOST`):
    - `DEPLOY_HOST`: The host to deploy to
    - `DEPLOY_PORT`: The SSH port
    - `DEPLOY_USER`: The user to deploy as
    - `DEPLOY_KEY`: The private key to use for deployment
        - generate a new key `ssh-keygen -t ed25519 -C "deploy@my-repo"`
        - Add the public key to the server's `~/.ssh/authorized_keys` file `ssh-copy-id -i {the_key} {user}@{host}
        - Set the private key as the value of the `DEPLOY_KEY` github secret
