# LibreSign organization automation

This repository centralizes shared GitHub organization automation for LibreSign and LibreCodeCoop.

It helps keep repository governance consistent as the project grows, including branch protection policies, controlled exceptions required by project workflows, and automated validation of the configuration that manages those policies.

The repository currently delivers:

- consistent branch protection rules across public repositories;
- automatic support for Nextcloud translation workflows where required;
- reduced administrative access scope for automation;
- automated checks that help prevent regressions in repository governance.

Technical and operational details are kept in [`docs/`](docs/):

- [Ruleset synchronization](docs/ruleset-sync.md)
- [Testing and validation](docs/testing.md)
