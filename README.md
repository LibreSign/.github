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
reconcile repository rulesets. The `libresign-required-ci` policy targets the
default branch of `LibreSign/libresign`, but is intentionally **disabled**:
that repository does not yet publish a verified aggregate `ci-required` check.
Merging this configuration PR must not block merges on a missing check.

This policy requires exactly one stable context, `ci-required`, instead of
coupling governance to individual PHPUnit, Behat, Node, Playwright and quality
job names. Organization administrators may bypass the CI policy through a
pull request only, with the exception justified in the PR. The separate active
`libresign-dco` ruleset requires the existing `DCO` check with **no bypass**.
Existing Code Owner reviews and branch protections remain unchanged.

### Prerequisite: an actual CI aggregator

Before enabling the policy, implement and test `ci-required` in
`LibreSign/libresign`. It must be produced by an always-triggered pull-request
workflow and cover all required CI. A final job with `if: always()` and
`needs` can aggregate jobs in **one workflow**, including called reusable
workflows. It cannot depend on jobs from independent workflow runs. If the
current separate workflows remain, first introduce a reliable coordinator.
Do not create a green placeholder check.

Regression tests must show `ci-required` fails when a required test fails,
is cancelled, or is missing unexpectedly; skips must be explicitly justified
rather than accepted silently. Verify a passing PR, a failing PR and a rerun,
and ensure the required context is attached to the commit checked for merge.
When adding a required test, also update the coordinator contract.

### Controlled rollout

1. Implement and validate the real `ci-required` producer in the consumer.
2. Change `libresign-required-ci.enforcement` to `active` in a reviewed PR.
3. Run the [governance workflow](.github/workflows/github-governance-dry-run.yml)
   with `apply=false` and inspect the proposed changes.
4. Execute `apply=true` explicitly, verify the remote ruleset, and rerun Plan.

Merging this PR does not apply the new ruleset. Other repositories and stable
branches must opt in only after their aggregator has been validated.

The current `ruleset-sync` protected environment requires approval even for
scheduled plans. Unattended drift checking needs separate work; do not
expose the administration-write App credential to remove that approval.
