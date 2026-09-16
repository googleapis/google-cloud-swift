# Google Cloud Build support

This directory contains configuration files and scripts to support GCB (Google
Cloud Build) builds.

While GHA (GitHub Actions) are an excellent CI system, they can become expensive
for large projects such as this one. As Googlers, we have a lot more budget for
running builds on GCB. We can also run integration tests against production
using GCB.

GCB can perform these integration tests with relatively simple management for
authentication and authorization: the builds run using a service account
specific to our project. We can grant this service account the necessary
permissions to act on the test resources.

In contrast, if we wanted to use GHA for the same role, we would need to either
(1) download a service account key file and install it as a GHA secret, and
manually rotate this secret, or (2) configure workload identify federation
between GitHub and our project. Neither approach is very easy to reason about
from a security perspective.

## Managing Resources for Integration Test

Integration tests need resources in production. We will need pre-existing
databases, storage buckets, service accounts, and the configuration for the
builds themselves.

We have chosen Terraform to manage these resources. That makes it easy to audit
them, recreate the resources when needed, and we can always change to a
different IaaC platform if needed.

## Build Triggers and Swift Versions

We run CI builds in Cloud Build for pull requests and post-merge events.
Our policy is to support and test against the last 3 minor releases of Swift, plus
a post-merge build against Swift nightly.

### Trigger Architecture

Trigger definitions are managed via Terraform in `ci/gcb/builds/triggers/main.tf`.
The triggers use semantic names decoupled from specific Swift version numbers:
- `gcb-pr-minimum-swift` / `gcb-pm-minimum-swift`: runs `ci/gcb/minimum-swift.yaml`
  (unit tests against minimum supported version, currently 6.2).
- `gcb-pr-intermediate-swift` / `gcb-pm-intermediate-swift`: runs
  `ci/gcb/intermediate-swift.yaml` (unit tests against intermediate supported version,
  currently 6.3).
- `gcb-pr-unit-tests` / `gcb-pm-unit-tests`: runs `ci/gcb/scripted.yaml` (unit tests
  against latest supported version, currently 6.4).
- `gcb-pm-nightly-swift`: runs `ci/gcb/nightly.yaml` (post-merge unit tests against
  `swiftlang/swift:nightly-bookworm`).
- Other builds (`gcb-pr-integration-tests`, `gcb-pr-docs`, `gcb-pr-full`, etc.): run
  `ci/gcb/scripted.yaml` against the latest supported version (6.4).

### Bumping Swift Versions

Because Cloud Build triggers read the YAML build configuration directly from the
repository at the checked-out PR commit, changing the supported Swift versions
does not require re-creating or modifying Terraform triggers:
1. Update `_SWIFT_VERSION` in `ci/gcb/minimum-swift.yaml` to the new minimum
   version.
2. Update `_SWIFT_VERSION` in `ci/gcb/intermediate-swift.yaml` to the new
   intermediate version.
3. Update `_SWIFT_VERSION` (and `_SWIFT_IMAGE` if applicable) in
   `ci/gcb/scripted.yaml` to the new latest version.
4. Update documentation in `README.md`, `supported-versions.md`, and
   `doc/contributor/howto-guide-set-up-development-environment.md`.

All of these changes can be tested and merged in a single GitHub pull request
without requiring any `terraform apply` step.
