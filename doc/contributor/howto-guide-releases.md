# How-To Guide: Creating Releases

This guide describes the release process for the `google-cloud-swift` SDK. It
covers both **normal incremental releases** (using `librarian bump`) and
**synchronized version bumps** (such as aligning all packages to a specific
version or dropping pre-release suffixes like `-preview`).

## Overview

Releases in `google-cloud-swift` follow a two-phase workflow:

1. **Release Preparation (Pull Request)**:
   - Update library versions in [`librarian.yaml`](../../librarian.yaml).
   - Update dependency version constraints in handwritten `Package.swift` manifests if shared dependencies were bumped.
   - Run `librarian generate --all` to update generated `Package.swift`, `README.md`, `Clients.swift`, and `PackageVersion.swift` files.
   - Validate the changes and merge the release pull request into `main`.
2. **Publishing and Tagging (Post-Merge)**:
   - Run `librarian publish` from the merged `main` commit to split each package subdirectory (`pkgs/swift-*` and `generated/swift-*`) into its standalone GitHub repository (`googleapis/swift-*`) and push version tags.
   - Tag the monorepo release commit on `upstream/main`.

## Prerequisites

Make sure your workstation meets the requirements in
[Set Up Development Environment](howto-guide-set-up-development-environment.md):

- Up-to-date Swift toolchain (`swift` and `swift-format`)
- Go (`go`)
- Protocol Buffer compiler (`protoc`) and `protoc-gen-swift`
- GitHub CLI (`gh`) authenticated with push access
- A clean working tree synchronized with `upstream/main`

## Normal Release Workflow (`librarian bump`)

For standard releases where changed libraries are incremented to their next
semantic version based on changes since the last monorepo release tag, use
`librarian bump`.

### Step 1: Create a Release Branch

Ensure your local `main` branch is up to date with `upstream/main`:

```bash
git checkout main
git pull --ff-only upstream main
git checkout -b chore-release-$(date +%Y-%m-%d)
```

### Step 2: Bump Library Versions

Retrieve the configured `librarian` version and run `librarian bump`:

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)

# Bump all libraries that have changes since the last release tag:
go run github.com/googleapis/librarian/cmd/librarian@${V} bump --all

# Or bump a single specific library (optionally overriding the target version):
# go run github.com/googleapis/librarian/cmd/librarian@${V} bump <library-name> --version <x.y.z>
```

> **Idempotency (`librarian bump` may change nothing)**: `librarian bump` is
> idempotent between releases—it only bumps a library **once** until the next
> release is tagged. It checks `git diff` against the last release tag to see if
> the library's version manifest (`Clients.swift` or `PackageVersion.swift`) was
> already updated since that tag. In principle, you could run `librarian bump` on
> every PR and it would only affect the version and generated code once per
> release cycle. If a library's version was already bumped in an earlier PR since
> the last release tag, `librarian bump` will leave it unchanged.
>
> **Version Manifests**: All Swift packages have a version manifest in their
> `Sources/` directory: GAPIC service packages maintain `Clients.swift`, while
> type-only, protobuf, and core packages maintain `PackageVersion.swift`. Both
> files record the package's version and are used by `librarian bump` to detect
> changes and enforce idempotency.

### Step 3: Update Handwritten `Package.swift` Manifests (If Needed)

If any core or shared packages (such as `swift-google-auth`, `swift-google-gax`,
`swift-google-wkt`, `swift-google-rpc`, `swift-google-iam-v1`,
`swift-google-longrunning`, or `swift-google-type`) had their version bumped,
update their `from:` version constraints in the handwritten `Package.swift`
manifests:

- [`Package.swift`](../../Package.swift) (root repository manifest)
- [`pkgs/swift-google-gax/Package.swift`](../../pkgs/swift-google-gax/Package.swift)
- [`pkgs/swift-google-cloud-storage/Package.swift`](../../pkgs/swift-google-cloud-storage/Package.swift)
- [`guide/Package.swift`](../../guide/Package.swift)

### Step 4: Tidy and Regenerate All Libraries

Run `librarian tidy` and `librarian generate --all` so that all generated
`Package.swift`, `README.md`, `Clients.swift`, and `PackageVersion.swift` files
reflect the updated versions and resolved dependency versions:

```bash
go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
```

### Step 5: Validate, Commit, and Open a Pull Request

Run formatting and validation checks:

```bash
./ci/lint.sh
./ci/generated.sh
```

Commit the changes and create the pull request:

```bash
git add .
git commit -m "chore: release circa $(date +%Y-%m-%d)"
git push -u origin chore-release-$(date +%Y-%m-%d)

gh pr create --draft \
  --title "chore: release circa $(date +%Y-%m-%d)" \
  --body "Bump library versions and regenerate client libraries for release."
```

---

## Synchronized Version Bump Strategy

When transitioning pre-release identifiers (for example, dropping the `-preview`
suffix) or synchronizing all libraries in the repository to a single uniform
version (such as `0.2.0`), `librarian bump --all` cannot be used directly because:

1. `librarian bump --all` derives the next version using semantic version rules that preserve pre-release suffixes (e.g., `0.1.0-preview` $\rightarrow$ `0.2.0-preview`) and only updates libraries modified since the last git tag.
2. `librarian bump --all` does not accept the `--version` flag.

To synchronize all library versions across the repository:

### Step 1: Create a Release Branch

```bash
git checkout main
git pull --ff-only upstream main
git checkout -b release-0.2.0
```

### Step 2: Update `librarian.yaml` Versions

Update `default_version` and every library's `version` field in
[`librarian.yaml`](../../librarian.yaml) to the target version (e.g., `0.2.0`):

```bash
sed -i -E 's/(default_version|version): 0\.[01]\.0-preview/\1: 0.2.0/g' librarian.yaml
```

### Step 3: Update Handwritten `Package.swift` Manifests

Update the dependency version constraints in all handwritten `Package.swift`
files to match the synchronized version:

```bash
sed -i -E 's/from: "0\.[01]\.0-preview"/from: "0.2.0"/g' \
  Package.swift \
  pkgs/swift-google-gax/Package.swift \
  pkgs/swift-google-cloud-storage/Package.swift \
  guide/Package.swift
```

### Step 4: Tidy and Regenerate All Libraries

Format `librarian.yaml` and regenerate all libraries so that every generated
package manifest, README, and version constant is updated to the new version:

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
```

### Step 5: Validate, Commit, and Open a Pull Request

Validate the repository formatting and tests:

```bash
./ci/lint.sh
./ci/generated.sh
```

Commit all modified files, push your branch, and open a pull request:

```bash
git add .
git commit -m "chore: release 0.2.0 version"
git push -u origin release-0.2.0

gh pr create --draft \
  --title "chore: release 0.2.0 version" \
  --body "$(cat <<'EOF'
Synchronize all library versions to `0.2.0` and drop the `-preview` suffix.

Fixes #<issue-number>
EOF
)"
```

---

## Publishing and Tagging After Merge

Once the release pull request has been reviewed and merged into `main`:

1. **Sync with `upstream/main`**:
   ```bash
   git checkout main
   git pull --ff-only upstream main
   ```

2. **Dry-Run Publish**:
   Verify that all modified packages split cleanly and check what tags will be pushed:
   ```bash
   V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
   go run github.com/googleapis/librarian/cmd/librarian@${V} publish --dry-run
   ```

3. **Publish Standalone Repositories**:
   Run `librarian publish` to perform subtree splits for each library (`pkgs/swift-*` and `generated/swift-*`), push the split commits to their respective standalone repositories (`googleapis/swift-*`), and tag each standalone repository with its new version:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} publish
   ```

4. **Tag the Monorepo Commit**:
   Tag the release commit in the `google-cloud-swift` monorepo so future `librarian bump --all` runs have an accurate baseline tag:
   ```bash
   git tag <release-tag>
   git push upstream <release-tag>
   ```
