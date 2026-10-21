# LibreSign organization configuration

This repository contains the GitHub organization configuration and automation
used by LibreSign.

LibreSign is an open-source digital signature platform for organizations that
need control over their document-signing infrastructure, integrations and data.

Commercial support, implementation and enterprise services are available through
LibreCode Coop.

- Product: https://libresign.coop/
- Services and support: https://librecode.coop/
- Sponsor the project: https://github.com/sponsors/LibreSign

Technical governance is powered by
`LibreCodeCoop/github-governance`. Implementation details belong in the
repository documentation rather than this README.

## Required CI and exceptional merges

The [organization governance configuration](governance.config.json) uses
[github-governance](https://github.com/LibreCodeCoop/github-governance) to
reconcile repository rulesets. The `libresign-required-ci` policy is enabled
for `LibreSign/libresign` on its default branch. Existing review and Code Owner
requirements remain in a separate ruleset. This is a first rollout, not an
organization-wide CI gate; other repositories and maintained stable branches
need their own verified check contexts before opting in.

GitHub auto-merge only waits for required checks. The policy names the actual
PR checks, including the Node, PHPUnit, Behat, Playwright and quality-summary
jobs. Keep names in sync with workflows when they change. A missing required
check blocks merge. Organization administrators may bypass the CI ruleset only
through a pull request, for a justified manual merge. Record the reason in
the PR; do not use auto-merge to bypass failing checks.

To roll out a policy change: review and merge the configuration PR, run the
[governance workflow](.github/workflows/github-governance-dry-run.yml) with
`apply=false`, check the per-repository plan, then explicitly run with
`apply=true`. Verify the applied ruleset and follow with another dry-run.
Neither merging this configuration nor a scheduled dry-run applies changes.

The current `ruleset-sync` protected environment requires approval even for
scheduled plans. The unattended drift check therefore needs separate work;
do not remove the approval or expose the administration-write App credential
just to make planning unattended.
