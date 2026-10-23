# Repository governance and CI

This repository maintains shared GitHub organization configuration for LibreSign.
The declarative source of truth is [`governance.config.json`](../governance.config.json);
the reconciliation engine is
[`LibreCodeCoop/github-governance`](https://github.com/LibreCodeCoop/github-governance).
The engine creates or updates repository-level rulesets for eligible public,
non-archived repositories. It does not make this an organization-level GitHub
ruleset.

## Policy layout

- `protected-branches` is selected by default for public, non-archived
  repositories. It protects their default branch and `stable*` branches and
  requires reviews, Code Owner approval and resolved review conversations.
- `libresign-dco` is selected for `LibreSign/libresign` on its default branch.
  Its desired configuration is **active** and requires the `DCO` context.
  Only `nextcloud-bot` (GitHub user ID `20296731`) may bypass this ruleset
  for direct Transifex translation pushes. Other contributors must pass
  the DCO check.
- `libresign-required-ci` is selected for `LibreSign/libresign` on its default
  branch. Its desired configuration is **disabled** while the repository lacks
  a validated aggregate `ci-required` check. It specifies one stable context
  rather than each PHPUnit, Behat, Node, Playwright or quality job.
- `organization-config-ci` is selected for `LibreSign/.github` and requires
  its own DCO, actionlint and zizmor checks.

The configuration describes desired policy; it does not prove a given ruleset
has already been applied remotely. Changes must pass the reconciliation process
described below.

## Contract for `ci-required`

Before changing `libresign-required-ci.enforcement` to `active`, introduce a
real `ci-required` check in `LibreSign/libresign`. It must run for relevant
pull requests and report the result of **all mandatory CI**. A job using
`if: always()` with `needs` can aggregate dependencies within a single
workflow, including reusable workflows. It cannot read dependencies in separate
workflow runs using `needs`; independently triggered workflows require a
different reliable coordination mechanism.

Do not publish a placeholder check that succeeds without inspecting tests.
Verify that a required failure, cancellation or unexpectedly missing result
prevents a green aggregate check. A legitimate skip must follow a documented
rule; a skipped mandatory test must not silently count as a success. Check
successful runs, failing runs, reruns and the GitHub commit that receives the
check. Changing mandatory tests also requires updating the aggregation
contract.

The status check rule specifies `strict_required_status_checks_policy: true`,
so an enabled policy would also require the branch to be current with its base
before merging.

## Exceptions and auto-merge

The CI ruleset allows `OrganizationAdmin` bypass in `pull_request` mode:
an administrator may exceptionally merge through a PR and should explain the
reason in that PR. This exception does **not** authorize bypass of the
separate DCO ruleset. Existing Code Owner and review requirements are defined
by a different ruleset.

The `nextcloud-bot` bypass applies only to the `libresign-dco` policy for
`LibreSign/libresign`. It uses `always` mode because the bot pushes
signed-off translations directly to `main`, without a PR status check.
This user-level bypass is not limited to files under `l10n/`.

Auto-merge only waits for checks configured as required; it does not wait
for every workflow. Do not enable automatic merging as a way to skip failing CI.

## Controlled rollout

1. Implement and test the aggregate `ci-required` producer in the consuming
   project.
2. Propose changing the desired `libresign-required-ci.enforcement` to
   `active` in a reviewed pull request.
3. Run [GitHub governance](../.github/workflows/github-governance-dry-run.yml)
   with `apply=false` and inspect the planned changes for all repositories.
4. Run the workflow again with `apply=true` only after explicit review.
   Verify the resulting remote rulesets, then run another dry-run.

Committing configuration alone does not apply rulesets. The current
`ruleset-sync` protected environment requires approval even for scheduled
planning runs; do not remove that protection or expose the GitHub App's
administration-write credentials simply to run plans unattended.

Other repositories and maintained stable branches must be assessed separately
before enabling a CI gate. See [testing and validation](testing.md) for the
checks provided by this organization configuration repository.
