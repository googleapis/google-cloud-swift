---
name: create-release
description: >-
  Use this skill to create a release for google-cloud-swift libraries,
  including normal incremental releases using `librarian bump` as well as
  synchronized version bumps (such as dropping pre-release suffixes like `-preview`
  or aligning all packages to a single version), regenerating affected packages,
  validating changes, opening a pull request, and publishing split repositories.
---

# Create Release

This skill guides the agent through creating a release for `google-cloud-swift`. It supports two release workflows:
1. **Normal Incremental Release (`librarian bump`)**: Bumps versions for libraries modified since the last release tag using `librarian bump`, regenerates code, updates handwritten manifests if needed, and opens a release pull request.
2. **Synchronized Version Bump**: Aligns all libraries across the repository to a specific target version (e.g., `0.2.0`) or transitions pre-release identifiers (such as dropping `-preview`).

Full contributor documentation is available in [How-To Guide: Creating Releases](../../../doc/contributor/howto-guide-releases.md).

--------------------------------------------------------------------------------

## Prerequisites and Environment Verification

Before preparing a release, verify that all required tools are installed and properly configured, as detailed in [Set Up Development Environment](../../../doc/contributor/howto-guide-set-up-development-environment.md):

1. **Swift (>= 6.2) & `swift-format`**:
   ```bash
   swift --version
   swift-format --version
   ```
2. **Go (Golang)**:
   ```bash
   go version
   ```
3. **Protocol Buffer Compiler (`protoc` >= v23.0) & `protoc-gen-swift` (1.38.1)**:
   ```bash
   protoc --version
   protoc-gen-swift --version
   ```
4. **GitHub CLI (`gh`)**:
   ```bash
   gh --version
   gh auth status
   ```

--------------------------------------------------------------------------------

## Workflow 1: Normal Incremental Release (`librarian bump`)

Use this workflow for standard releases where libraries with changes since the last monorepo release tag should be incremented to their next semantic version.

### Step 1: Create a Clean Branch

Ensure the local repository is clean and synchronized with `upstream/main`:

```bash
git checkout main
git pull --ff-only upstream main || git pull --ff-only origin main
git checkout -b chore-release-$(date +%Y-%m-%d)
```

### Step 2: Run `librarian bump`

Retrieve the configured `librarian` version and execute `librarian bump`:

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)

# Bump all libraries with changes since the last monorepo release tag:
go run github.com/googleapis/librarian/cmd/librarian@${V} bump --all

# Or bump a single specific library (optionally with a target version override):
# go run github.com/googleapis/librarian/cmd/librarian@${V} bump <library-name> --version <x.y.z>
```

> [!NOTE]
> **Idempotency (`librarian bump` may change nothing)**: `librarian bump` is idempotent between releases—it only bumps a library **once** until the next release is tagged. It checks `git diff` against the last release tag to see if `Clients.swift` or `PackageVersion.swift` was already updated since that tag. In principle, `librarian bump` could be run on every PR and it would only affect the generated code once per release cycle. If a library was already bumped since the last release tag, `librarian bump` will make no changes to it.
>
> **Version Manifests**: All Swift packages have a version manifest in their `Sources/` directory: GAPIC service packages maintain `Clients.swift`, while type-only, protobuf, and core packages maintain `PackageVersion.swift`. Both files record the package's version and are used by `librarian bump` to detect changes and enforce idempotency.

### Step 3: Update Handwritten `Package.swift` Dependencies (If Needed)

If any core/shared packages (`swift-google-auth`, `swift-google-gax`, `swift-google-wkt`, `swift-google-rpc`, `swift-google-iam-v1`, `swift-google-longrunning`, `swift-google-type`) were bumped in `librarian.yaml`, update their `from:` version constraints in the handwritten `Package.swift` files:
- [`Package.swift`](../../../Package.swift) (root manifest)
- [`pkgs/swift-google-gax/Package.swift`](../../../pkgs/swift-google-gax/Package.swift)
- [`pkgs/swift-google-cloud-storage/Package.swift`](../../../pkgs/swift-google-cloud-storage/Package.swift)
- [`guide/Package.swift`](../../../guide/Package.swift)

### Step 4: Tidy and Regenerate All Libraries

Run `librarian tidy` and `librarian generate --all` to update all generated `Package.swift`, `README.md`, `Clients.swift`, and `PackageVersion.swift` files with the new version numbers and resolved dependency versions:

```bash
go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
```

### Step 5: Validate Changes

Run formatting and package checks:

```bash
./ci/lint.sh
./ci/generated.sh
```

### Step 6: Commit and Create Pull Request

1. **Commit Changes**:
   ```bash
   git add .
   git commit -m "chore: release circa $(date +%Y-%m-%d)"
   ```

2. **Push Branch and Create Draft PR**:
   ```bash
   git push -u origin chore-release-$(date +%Y-%m-%d)

   gh pr create --draft \
     --title "chore: release circa $(date +%Y-%m-%d)" \
     --body "$(cat <<'EOF'
   Bump library versions and regenerate client libraries for release.
   EOF
   )"
   ```
   *(If pushing to a fork remote such as `personal`, specify `--repo googleapis/google-cloud-swift --head <username>:chore-release-$(date +%Y-%m-%d)`.)*

--------------------------------------------------------------------------------

## Workflow 2: Synchronized Version Bump / Pre-Release Transition

Use this workflow when aligning all libraries in the monorepo to a single uniform version (e.g., `0.2.0`) or removing/changing pre-release tags (such as dropping `-preview`).

`librarian bump --all` cannot be used for this scenario because:
- It derives next versions via `semver.DeriveNext`, which preserves pre-release suffixes (`0.1.0-preview` $\rightarrow$ `0.2.0-preview`).
- It does not support the `--version` flag alongside `--all`.

### Step 1: Create a Clean Branch

```bash
git checkout main
git pull --ff-only upstream main || git pull --ff-only origin main
git checkout -b release-<target-version>
```

### Step 2: Update `librarian.yaml` Versions

Update `default_version` and every library's `version` field in [`librarian.yaml`](../../../librarian.yaml) to `<target-version>` (e.g., `0.2.0`):

```bash
TARGET_VERSION="0.2.0"
sed -i -E "s/(default_version|version): 0\.[01]\.0-preview/\1: ${TARGET_VERSION}/g" librarian.yaml
```

### Step 3: Update Handwritten `Package.swift` Manifests

Update dependency version constraints in all handwritten `Package.swift` manifests:

```bash
sed -i -E "s/from: \"0\.[01]\.0-preview\"/from: \"${TARGET_VERSION}\"/g" \
  Package.swift \
  pkgs/swift-google-gax/Package.swift \
  pkgs/swift-google-cloud-storage/Package.swift \
  guide/Package.swift
```

### Step 4: Tidy and Regenerate All Libraries

Run `librarian tidy` and `librarian generate --all`:

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
```

### Step 5: Validate, Commit, and Open Pull Request

1. **Validate**:
   ```bash
   ./ci/lint.sh
   ./ci/generated.sh
   ```

2. **Commit and Push**:
   ```bash
   git add .
   git commit -m "chore: release ${TARGET_VERSION} version"
   git push -u origin release-${TARGET_VERSION}
   ```

3. **Create Draft Pull Request**:
   ```bash
   gh pr create --draft \
     --title "chore: release ${TARGET_VERSION} version" \
     --body "$(cat <<EOF
   Synchronize all library versions to \`${TARGET_VERSION}\` and drop the \`-preview\` suffix.

   Fixes #<issue-number>
   EOF
   )"
   ```

--------------------------------------------------------------------------------

## Post-Merge Publishing and Tagging

After the release pull request is merged into `main`:

1. **Checkout and Pull Merged `main`**:
   ```bash
   git checkout main
   git pull --ff-only upstream main
   ```

2. **Dry-Run Publish**:
   Verify that all packages split cleanly and check which tags will be pushed:
   ```bash
   V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
   go run github.com/googleapis/librarian/cmd/librarian@${V} publish --dry-run
   ```

3. **Publish Standalone Repositories**:
   Execute `librarian publish` to split each package subdirectory (`pkgs/swift-*` and `generated/swift-*`) via `git subtree split`, push to its standalone repository (`googleapis/swift-*`), and push the version tag on each standalone repository:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} publish
   ```

4. **Tag the Monorepo Commit**:
   Tag the release commit on the monorepo so future `librarian bump --all` runs have an accurate baseline tag:
   ```bash
   git tag <release-tag>
   git push upstream <release-tag>
   ```
