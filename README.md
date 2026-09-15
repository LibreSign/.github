# LibreSign organization automation

This repository contains shared organization metadata and automation used to keep repository rulesets consistent across LibreSign and LibreCodeCoop public repositories.

## Ruleset synchronization

`.github/rulesets/default-branches.json` is the source of truth for the default repository ruleset. The scheduled workflow `.github/workflows/sync-rulesets.yml` applies it to public, non-archived repositories that are available to the ruleset GitHub App installation.

The ruleset protects the default branch and `stable*` branches. It prevents deletion and non-fast-forward updates and requires pull requests, one approval, CODEOWNERS approval and resolved review threads.

### Nextcloud apps

A repository is considered a Nextcloud app when `appinfo/info.xml` exists in its default branch.

For these repositories, the sync script adds the `nextcloud-bot` GitHub user to the ruleset bypass actors with `bypass_mode: always`. The actor is pinned by the stable GitHub user ID `20296731`; the username is used only for documentation and log messages.

A `404` while checking `appinfo/info.xml` means the repository is not a Nextcloud app. Other API errors abort synchronization for that repository so a temporary authorization or GitHub API failure cannot silently remove the bot bypass.

## Running the synchronization

The normal command synchronizes every public, non-archived repository for the selected organization:

```bash
ORG=LibreSign ./scripts/sync-rulesets.sh
```

To inspect drift without modifying any repository:

```bash
ORG=LibreSign ./scripts/sync-rulesets.sh --check
```

To limit the operation to one repository:

```bash
ORG=LibreSign ./scripts/sync-rulesets.sh --repo LibreSign/libresign
```

The command requires `gh`, `jq` and a GitHub token with repository administration permission. The scheduled workflow generates a short-lived GitHub App token with only `administration: write` in addition to the workflow's read-only contents permission.

## Tests

The shell behavior and policy invariants are tested with Bats:

```bash
bats tests
```

Shell scripts are checked with ShellCheck. GitHub Actions workflows are checked with actionlint and zizmor in `.github/workflows/quality.yml`.

The pull request quality workflow does not use the ruleset GitHub App credentials and has only `contents: read` permission.

## GitHub Actions dependencies

Third-party actions are pinned to full commit SHAs. Dependabot is configured to propose weekly GitHub Actions updates so immutable pins can stay current.
