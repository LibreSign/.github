# Ruleset synchronization

This repository keeps branch protection rulesets consistent across public repositories in the LibreSign and LibreCodeCoop organizations.

## Source of truth

`.github/rulesets/default-branches.json` defines the desired ruleset for default branches and `stable*` branches.

The synchronization script applies this policy to public, non-archived repositories available to the ruleset GitHub App installation.

## Nextcloud apps

A repository is treated as a Nextcloud app when `appinfo/info.xml` exists in its default branch.

For these repositories, the synchronization adds `nextcloud-bot` as a bypass actor with `bypass_mode: always`. The GitHub actor is pinned by user ID `20296731`.

A `404` while checking `appinfo/info.xml` means the repository is not a Nextcloud app. Other API errors abort synchronization so transient failures cannot silently remove the bot bypass.

## Running locally

Synchronize all public, non-archived repositories in an organization:

```bash
ORG=LibreSign ./scripts/sync-rulesets.sh
```

Check for drift without modifying repositories:

```bash
ORG=LibreSign ./scripts/sync-rulesets.sh --check
```

Limit synchronization to one repository:

```bash
ORG=LibreSign ./scripts/sync-rulesets.sh --repo LibreSign/libresign
```

The command requires `gh`, `jq`, and a GitHub token with repository administration permission.

## Privileged workflow

`.github/workflows/sync-rulesets.yml` discovers public repositories with the read-only workflow token. It then creates one short-lived GitHub App token per repository, scoped to that repository with `administration: write`, and runs the sync using `--repo`.

The workflow serializes synchronization runs and has execution timeouts to reduce the risk of concurrent administrative writes or stuck privileged jobs.
