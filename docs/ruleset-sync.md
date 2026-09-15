# Ruleset synchronization

This repository keeps branch protection rulesets consistent across public repositories in the LibreSign and LibreCodeCoop organizations.

## Policy composition

Ruleset policies are composed in two layers so repository-specific requirements do not make the shared policy harder to understand.

### Base policy

`.github/rulesets/default-branches.json` applies to every public, non-archived repository managed by the synchronization.

It protects the default branch and `stable*` branches. This is also the policy that receives the Nextcloud translation exception described below.

### Repository-specific policies

Additional ruleset files are applied only to repositories explicitly selected by `ruleset_files_for_repository()` in `scripts/sync-rulesets.sh`.

Currently, `.github/rulesets/libresign-github-ci.json` applies only to `LibreSign/.github` and only to its default branch. It requires the repository's Bats, ShellCheck, actionlint, and zizmor checks to pass before merge.

Repository-specific policies must stay separate from the base policy unless the rule is intended for all managed repositories.

## Nextcloud apps

A repository is treated as a Nextcloud app when `appinfo/info.xml` exists in its default branch.

For these repositories, the synchronization adds `nextcloud-bot` as a bypass actor with `bypass_mode: always` to the base ruleset. Because the base ruleset protects both the default branch and `stable*`, translation pushes keep working on maintained stable branches as well.

The GitHub actor is pinned by user ID `20296731`.

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
