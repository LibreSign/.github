# Testing and validation

The repository uses focused checks so each validation type has its own setup and failure signal.

## Bats

Bats tests cover synchronization behavior and ruleset policy invariants.

Run locally with:

```bash
bats tests
```

The test suite covers Nextcloud and non-Nextcloud repositories, API error handling, bypass idempotency, repository targeting, ruleset normalization, and policy invariants.

## ShellCheck

Shell scripts are analyzed independently with ShellCheck:

```bash
shellcheck scripts/*.sh
```

## actionlint

GitHub Actions workflow syntax and expressions are validated by the dedicated `actionlint` workflow.

## zizmor

GitHub Actions security is audited by the dedicated `zizmor` workflow. Analysis runs without access to the ruleset GitHub App credentials.

## Dependency updates

Third-party Actions are pinned to full commit SHAs. Dependabot checks GitHub Actions dependencies weekly and applies a seven-day cooldown before proposing updates.
