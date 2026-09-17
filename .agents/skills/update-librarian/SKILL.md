---
name: update-librarian
description: >-
  Use this skill to update the librarian code generator version in librarian.yaml,
  regenerate all client libraries with the new version, inspect and verify expected
  generator changes, validate packages, and open a draft pull request with detailed
  context on the expected changes included in the regeneration.
---

# Update Librarian Version

This skill guides the agent through updating the `librarian` code generator version in [`librarian.yaml`](../../../librarian.yaml), regenerating all client libraries in `google-cloud-swift`, verifying that the regenerated code matches the expected generator features or fixes, validating the packages, and opening a draft pull request with clear context explaining the expected changes.

--------------------------------------------------------------------------------

## Prerequisites and Environment Verification

Before updating `librarian` and regenerating code, verify that all required tools and compilers are installed and meet the version requirements, as detailed in the [Set Up Development Environment Guide](../../../doc/contributor/howto-guide-set-up-development-environment.md):

1. **Swift (>= 6.2) & `swift-format`**:
   ```bash
   swift --version
   swift-format --version
   ```
   *Requirement*: Swift >= 6.2 using the Swiftly toolchain, with `swift-format` installed and accessible in `$PATH`. If `swift --version` references Apple's system toolchain (`swiftlang`), switch using `swiftly install latest && swiftly link`.

2. **Go (Golang)**:
   ```bash
   go version
   ```
   *Requirement*: Go is required to execute `librarian`.

3. **Protocol Buffer Compiler (`protoc` >= v23.0)**:
   ```bash
   protoc --version
   ```
   *Requirement*: `protoc` >= v23.0 in `$PATH`.

4. **Swift Protobuf Plugin**:
   - `protoc-gen-swift` (version 1.38.1):
     ```bash
     protoc-gen-swift --version
     ```
   *Installation if missing*:
   ```bash
   mkdir -p "${HOME}/.local/bin"
   BUILD_DIR=$(mktemp -d)
   git clone --depth 1 --branch "1.38.1" https://github.com/apple/swift-protobuf.git "${BUILD_DIR}/swift-protobuf"
   (cd "${BUILD_DIR}/swift-protobuf" && swift build -c release && cp .build/release/protoc-gen-swift "${HOME}/.local/bin/")
   rm -rf "${BUILD_DIR}"
   export PATH="${HOME}/.local/bin:${PATH}"
   ```

5. **GitHub CLI (`gh`)**:
   ```bash
   gh --version
   gh auth status
   ```
   *Requirement*: `gh` must be authenticated to inspect `googleapis/librarian` commits/PRs and create pull requests.

--------------------------------------------------------------------------------

## Step-by-Step Workflow

### Step 1: Determine Target Version and Gather Change Context

Normally, we bump the version of `librarian` to take advantage of a specific new feature or bug fix in the code generator. Before regenerating, gather context on what changed between the current and target versions.

1. **Record the Current Librarian Version (`OLD_V`)**:
   ```bash
   OLD_V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
   echo "Current version: ${OLD_V}"
   ```

2. **Determine the Target Librarian Version (`V`)**:
   - **Latest on `main` (Default)**:
     ```bash
     V=$(GOPROXY=direct go list -m -f '{{.Version}}' github.com/googleapis/librarian@main)
     ```
   - **Specific Commit, Branch, or Tag (if requested by the user)**:
     ```bash
     V=$(GOPROXY=direct go list -m -f '{{.Version}}' github.com/googleapis/librarian@<commit-or-branch>)
     ```

3. **Identify Expected Changes from `googleapis/librarian`**:
   - If the user provided specific context (e.g., a feature name, bug fix, or a `googleapis/librarian` PR link), note those details.
   - Extract the git refs/SHAs from `OLD_V` and `V` (for Go pseudo-versions like `v0.44.1-0.20260917024435-e0e498e8eaa7`, the commit hash is the 12-character suffix after the last `-`; for tagged versions, use the tag directly):
     ```bash
     OLD_REF="${OLD_V##*-}"
     NEW_REF="${V##*-}"
     ```
   - Query the commit log between the two versions in `googleapis/librarian` using `gh`:
     ```bash
     gh api "repos/googleapis/librarian/compare/${OLD_REF}...${NEW_REF}" \
       --jq '.commits[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'
     ```
   - Look for commits or PRs affecting Swift generation (`swift`, `generator`, etc.). If needed, inspect specific PR details or commit messages:
     ```bash
     gh pr view <pr-number> --repo googleapis/librarian
     ```

### Step 2: Create a Clean Branch

Ensure your local branch is synchronized with upstream `main` before starting:

```bash
git checkout main
git pull --ff-only upstream main || git pull --ff-only origin main
```

Create a new branch. Use a descriptive name if updating for a specific feature/fix, or a dated branch for general updates:

```bash
# Descriptive branch (preferred when targeting a specific feature/fix):
git checkout -b chore-update-librarian-<short-feature-or-fix-name>

# Or standard dated branch:
git checkout -b chore-update-librarian-circa-$(date +%Y-%m-%d)
```

### Step 3: Update `librarian.yaml` and Regenerate All Libraries

Follow the instructions in [Generated Code Maintenance](../../../doc/contributor/howto-guide-generated-code-maintenance.md#update-librarian):

1. **Set the New Librarian Version in `librarian.yaml`**:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} config set version ${V}
   ```

2. **Regenerate All Client Libraries**:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
   ```

3. **Format and Sort `librarian.yaml`**:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
   ```

### Step 4: Inspect Diff and Verify Expected Changes

Before running validation or committing, carefully inspect the generated diff to confirm that the changes in `generated/` align with the expected generator changes identified in Step 1:

```bash
git status
git diff --stat
git diff generated/ | head -n 100
```

- **Verify Expected Output**: Check representative files in `generated/` to confirm that the new generator feature or bug fix took effect as intended (e.g., updated HTTP bindings, request option passing, enum serialization, documentation formatting, or file naming).
- **Check for Unintended Changes**: Ensure no unexpected regressions or unrelated modifications were introduced.
- **Summarize the Diff**: Take note of the concrete code patterns that changed in `generated/` so you can clearly describe them in the pull request body.

> [!IMPORTANT]
> **Never manually edit code inside `generated/`**. All contents inside `generated/` must be produced exclusively by `librarian`.

### Step 5: Handle Troubleshooting and Test Adjustments

1. **Generation Errors**:
   If `librarian generate --all` fails, consult the [Librarian Playbook](../../../doc/contributor/librarian-playbook.md) for common fixes (such as adding missing `ApiPackages` entries or `library_name_override` in [`librarian.yaml`](../../../librarian.yaml)).

2. **Unit / Integration Test Adjustments**:
   Bumping `librarian` for generator changes (such as changing how enums are serialized, how request options are passed, or how method signatures are structured) may affect existing unit or integration tests outside `generated/`. If tests fail due to intentional generator behavior changes, update the affected tests to align with the new generated code behavior.

### Step 6: Validate the Changes

1. **Validate Generated Packages**:
   ```bash
   ./ci/generated.sh
   ```
   Or run targeted tests on modified packages:
   ```bash
   swift test --package-path generated/<modified-library-name>
   ```

2. **Lint Code**:
   ```bash
   ./ci/lint.sh
   ```

3. **Run Repository Tests**:
   If the generator change alters runtime behavior, serialization, or interfaces used by handwritten code/tests:
   ```bash
   ./ci/test.sh
   ```

### Step 7: Commit the Changes

Stage all modified files and commit using the Conventional Commits format. Include a concise explanation of the expected changes in the commit body:

```bash
git add .
git commit -m "chore: update librarian with <feature-or-fix>" -m "<Brief description of expected changes in generated code>"
```

*Note*: Use `feat:` instead of `chore:` if the librarian update introduces a new user-facing feature in the generated client libraries (e.g., `feat: update librarian with serialize-enums-as-strings`). For general maintenance updates, use `chore: update librarian circa $(date +%Y-%m-%d)`.

### Step 8: Push and Create a Draft Pull Request with Context

1. **Push Branch to Origin**:
   ```bash
   git push -u origin HEAD
   ```

2. **Create Draft Pull Request with GitHub CLI (`gh`)**:
   Always open the pull request in **draft mode** using `--draft`. The PR description **must** include context about the version bump and what expected changes are included in the regeneration:

   ```bash
   gh pr create --draft \
     --title "<commit-title>" \
     --body "$(cat <<'EOF'
   Update `librarian` from `<OLD_V>` to `<V>` ([compare](https://github.com/googleapis/librarian/compare/<OLD_REF>...<NEW_REF>)) and regenerate all client libraries.

   ### Context & Expected Changes
   - **Generator Change**: <Explain the new feature, improvement, or bug fix from googleapis/librarian, linking to relevant librarian PRs/commits if applicable>
   - **Regeneration Impact**: <Describe the concrete changes observed in `generated/`, e.g., how generated methods, models, transport calls, or docs changed>

   Fixes #<issue-number-if-applicable>
   EOF
   )"
   ```

   *Note*: Omit the `Fixes #<issue-number-if-applicable>` line if there is no associated tracking issue in `google-cloud-swift`.

3. **Report PR Link**:
   Provide the created draft PR URL and a summary of the version bump and regenerated changes to the user.
