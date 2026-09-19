# Testing and validation

Shared governance behavior, policy composition, repository discovery and
ruleset reconciliation are tested in `LibreCodeCoop/github-governance`.

This repository validates its LibreSign-specific integration:

- `actionlint` validates GitHub Actions syntax and expressions;
- `zizmor` audits GitHub Actions security;
- the `GitHub governance` workflow performs scheduled and configuration-change
  dry-runs;
- manual reconciliation remains dry-run unless `apply=true` is explicitly
  selected;
- GitHub App credentials are protected by the `ruleset-sync` environment.

Third-party Actions are pinned to full commit SHAs.
