# Confidential security advisory access

LibreSign uses a dedicated, **secret** organization team, `security-response`,
for coordinated remediation of privately reported vulnerabilities. The team is
separate from `maintainers`. Membership in one does not automatically imply
membership in the other. The team is not granted repository-wide access merely
to view advisories.

## Responsibilities and authority

- **Maintainers:** code review, normal repository maintenance, stable branch
  support and CI. Repository `Maintain` is **not** advisory administration.
- **Security response:** confidential triage, investigation, remediation,
  review and coordination within advisories to which the team is invited.
  Advisory collaboration grants advisory write access, not the organization
  `Security Manager` role or unrestricted administration of all advisories.
- **Advisory administrators:** repository administrators and organization
  owners authorize collaborators, the security fork merge, disclosures, CVE
  requests, and publication. Publication requires a separate human decision
  after confirming the support matrix, available fixes and reporter agreement;
  no advisory-access workflow publishes, merges, changes state or requests a CVE.

A security-response team maintainer and an organization owner jointly review
membership changes when possible. Add only active organization members with
a demonstrated security response responsibility; the intended roster is
maintained privately in GitHub team settings, **not** in this public repository.
To revoke access, remove a former responder from `security-response` and
review any advisory-specific individual invitations or other inherited roles
that may independently retain access. Review membership after personnel or
role changes and before any coordinated disclosure.

## How an advisory receives access

Advisory administrators can add `security-response` through **Security >
Advisories > Collaborators**, or use the dedicated reconciler described below.
A review request on a pull request does not grant access to a private advisory.
The reporter and any other collaborators must be preserved. Access to the
associated temporary private fork is managed by GitHub through the advisory;
ordinary fork repository-collaborator endpoints do not always expose this
access. The invited member should confirm they can open the advisory and fork
in their own authenticated session.

## Declarative, scoped reconciliation

[`security-advisory-access.config.json`](../security-advisory-access.config.json)
contains only the repository, team slug and adoption cutoff. It never contains
GHSA identifiers, embargoed descriptions, reporter identities or private fork
paths. The reconciler is deliberately isolated from the generic repository
ruleset reconciler: confidential advisory credentials cannot be used to alter
organization rulesets or product CI.

The workflow runs hourly **only after it is enabled**. It reads repository
advisories and considers only unpublished `draft` or `triage` advisories created
on or after the adoption timestamp. Older advisories require explicit invitation
by an advisory administrator; this prevents unintended retroactive disclosure.
For a missing team it sends only the `collaborating_teams` field, preserving
existing teams and individual collaborators. Repeated runs are idempotent.
The code never changes state, releases, CVEs, forks, credits or other advisory
metadata. Workflow logs contain no advisory names, IDs, counts or paths.
Failures are not silently ignored; they are reported without identifying the
private advisory.

### One-time GitHub App setup

A dedicated GitHub App is required because no currently installed application
has `Repository security advisories: write`. Register it with only that
repository permission and install it on **LibreSign/libresign only**. Do not
reuse the organization ruleset administrator App, an organization-wide
`Security Manager` role, or a personal access token. GitHub has no narrower
API permission specifically for changing advisory collaborators, so this
repository-level advisory write permission is a residual risk. Keep the App
private key in an environment secret, protect the workflow through branch
rules and Code Owner review, and rotate the key if the responder roster or
administration changes.

In `LibreSign/.github`, configure the dedicated `security-advisory-access`
Actions environment with `ADVISORY_APP_CLIENT_ID` (environment variable) and
`ADVISORY_APP_PRIVATE_KEY` (environment secret). Restrict deployment to
protected branches. The workflow itself restricts execution to `main` and
requests a token valid only for the `libresign` repository.

Set repository variable `ADVISORY_ACCESS_ENABLED=true` once the App is installed
and credentials are configured; initially leave `ADVISORY_ACCESS_AUTO_APPLY`
set to `false`. Run **Reconcile private advisory access** manually with
`apply=false` to verify credentials and a read-only pass. After reviewing
this successful run, enable hourly automatic grants by setting
`ADVISORY_ACCESS_AUTO_APPLY=true`. Manual runs with `apply=true` use the
same tightly scoped logic. Disabling either variable stops scheduled writes.

The workflow cannot subscribe to unpublished draft advisory creation through
the published-only `repository_advisory` webhook. Periodic reconciliation
is therefore used instead. It does not widen access for historical advisories.

### Auditing

Authorized organization owners should periodically compare active team
membership, explicit advisory collaborators and GitHub audit-log events where
available. Never paste unpublished advisory API responses or fork URLs into
public issues, PRs, CI logs or this repository. The team must have no direct
repository grants unless independently justified. Check the GitHub App's
installation scope and permissions when reviewing the automation.

Changes to the secret team, the access cutoff, the App installation, or the
advisory collaboration policy are security-sensitive and require reviewed
human authorization. They are separate from authorization to disclose an
advisory or publish a release.
