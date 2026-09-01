---
name: onboard-new-library
description: >-
  Use this skill to onboard a new Google Cloud library or service to the Swift SDK,
  verify required development environment tools, check if target protos exist in the current locked source SHA,
  generate code using librarian, validate generated packages, and create a draft pull request
  that automatically fixes referenced GitHub issues upon merge.
---

# Onboard New Library

This skill guides the agent through the complete end-to-end process of onboarding a new Google Cloud client library in `google-cloud-swift`. It covers environment verification, checking for source availability, code generation via `librarian`, troubleshooting common generation issues, package validation, and opening a draft pull request via the GitHub CLI.

--------------------------------------------------------------------------------

## Prerequisites and Environment Verification

Before running code generation, verify that all required tools and compilers are installed and meet the version requirements, as detailed in the [Set Up Development Environment Guide](../../../doc/contributor/howto-guide-set-up-development-environment.md):

1. **Swift (>= 6.2) & `swift-format`**:
   ```bash
   swift --version
   swift-format --version
   ```
   *Requirement*: Swift >= 6.2 using the Swiftly toolchain, with `swift-format` installed and accessible in `$PATH`. If the `swift --version` output references Apple's system toolchain (`swiftlang`), switch using `swiftly install latest && swiftly link`.

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
   *Requirement*: `gh` must be authenticated to create pull requests.

--------------------------------------------------------------------------------

## Step-by-Step Workflow

### Step 1: Identify Target Library and Referenced GitHub Issues

1. **Extract Proto Path / Service Name**:
   Determine the target API path from the request (e.g., `google/cloud/kms/v1`, `google/cloud/ftp/v1`, `google/cloud/workloadidentity/v1`).
2. **Determine Library Name**:
   Convert the proto path to the librarian library name (e.g., `google/cloud/kms/v1` -> `google-cloud-kms-v1`).
3. **Extract Issue References**:
   Check if the user or trigger mentioned a GitHub issue (e.g., `https://github.com/googleapis/google-cloud-swift/issues/419`, `Fixes #419`, or `#417`). Record the issue number so the PR can close it when merged.

### Step 2: Create a Clean Feature Branch

Ensure your local branch is synchronized with upstream `main` before starting:

```bash
git checkout main
git pull --ff-only upstream main || git pull --ff-only origin main
```

Create a descriptive feature branch:

```bash
git checkout -b feat-<library-name>-generate-library
```

*Example*:
```bash
git checkout -b feat-google-cloud-ftp-v1-generate-library
```

### Step 3: Run Librarian Code Generation

Follow the procedures outlined in [Generated Code Maintenance](../../../doc/contributor/howto-guide-generated-code-maintenance.md):

1. **Retrieve Librarian Version**:
   ```bash
   V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
   ```

2. **Check If Source SHA Update is Needed**:
   Onboarding requests are frequently for newly released APIs or protos that do not yet exist in the `sources.googleapis` (or `sources.discovery`) commit SHA currently locked in [`librarian.yaml`](../../../librarian.yaml).

   - If the target proto or discovery spec does not exist in the currently locked revision (or if `librarian add` / `librarian generate` fails because the proto files are not found):
     - **DO NOT** update the source SHA inside the feature branch (source SHA updates regenerate all libraries and belong in a separate repository-wide `chore` PR).
     - **Abort the onboarding workflow**.
     - **Notify the user** that the target proto is missing from the locked source revision in `librarian.yaml`.
     - **Switch to the [Update Code Generation Sources Skill](../update-code-generation-sources/SKILL.md)** to update generation sources first in a dedicated branch/PR before proceeding with onboarding.

3. **Add the Library to [`librarian.yaml`](../../../librarian.yaml)**:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} add <proto-path>
   ```
   *Example*:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} add google/cloud/ftp/v1
   ```

4. **Generate the Library Code**:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} generate <library-name>
   ```
   *Example*:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} generate google-cloud-ftp-v1
   ```

### Step 4: Handle Common Generation Errors (Troubleshooting)

If `librarian generate` fails, consult [Librarian Playbook](../../../doc/contributor/librarian-playbook.md) for standard resolutions:

1. **PascalCase / Module Name Override Required**:
   - *Symptom*:
     ```text
     librarian: generate library "google-cloud-...": default library name for ... needs override.
     Other languages with PascalCase style deviate from the default name for this library...
     ```
   - *Resolution*: Add `library_name_override` under the library entry in [`librarian.yaml`](../../../librarian.yaml):
     ```yaml
       - name: <library-name>
         version: 0.0.0-preview
         copyright_year: "2026"
         swift:
           library_name_override: <PascalCaseName>
     ```
     *(Note: Follow Swift acronym conventions, e.g., `GoogleIAMV1`, `GoogleCloudFTPV1`)*.
   - Run `go run github.com/googleapis/librarian/cmd/librarian@${V} tidy` and re-run the `generate` command.

2. **Missing Package in `ApiPackages`**:
   - *Symptom*:
     ```text
     librarian: generate library "...": package "google.xxx" not found in ApiPackages
     ```
   - *Resolution*: Add the missing package under `default -> swift -> dependencies` in [`librarian.yaml`](../../../librarian.yaml):
     ```yaml
     default:
       swift:
         dependencies:
           - name: <DependencyModuleName>
             path: generated/<dependency-library-name>
             api_package: <protobuf.package.name>
     ```
   - Run `go run github.com/googleapis/librarian/cmd/librarian@${V} tidy` and re-run the `generate` command.

3. **Proto or Service Not Found in Source**:
   - *Symptom*:
     `librarian add` or `librarian generate` cannot locate the proto path or reports that the API does not exist.
   - *Context*: The proto specification is new and only exists in more recent commits of `googleapis` (or `discovery`) than the one currently pinned in [`librarian.yaml`](../../../librarian.yaml).
   - *Resolution*:
     1. Abort the onboarding feature branch.
     2. Notify the user that the proto is missing from the locked source revision in `librarian.yaml`.
     3. Use the [Update Code Generation Sources Skill](../update-code-generation-sources/SKILL.md) to update the source SHA and regenerate all libraries in a dedicated `chore` branch/PR.
     4. Once merged, return to the onboarding workflow on the updated `main` branch.

### Step 5: Validate the Generated Code

1. **Build and Test the Generated Package**:
   ```bash
   swift test --package-path generated/<library-name>
   ```

2. **Lint the Generated Package**:
   ```bash
   swift-format lint -r generated/<library-name>/Sources generated/<library-name>/Tests
   ```

3. **Tidy Configuration**:
   ```bash
   go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
   ```

4. **Verify Clean Status**:
   ```bash
   git status
   ```
   Ensure only `librarian.yaml` and files under `generated/<library-name>/` are modified or created.

> [!IMPORTANT]
> **Never manually edit code inside `generated/`**. All code in `generated/` is managed by `librarian`.

### Step 6: Commit the Changes

Follow Conventional Commits format:

```bash
git add .
git commit -m "feat(<short-service-name>): generate library"
```

*Examples*:
- `git commit -m "feat(ftp/v1): generate library"`
- `git commit -m "feat(kms/v1): generate library"`
- `git commit -m "feat(workloadidentity/v1): generate library"`

### Step 7: Push and Create a Draft Pull Request

1. **Push Branch to Origin**:
   ```bash
   git push -u origin feat-<library-name>-generate-library
   ```

2. **Create Draft Pull Request with GitHub CLI (`gh`)**:
   Always open the pull request in **draft mode** using `--draft`.

   - **If a GitHub issue was referenced**:
     Include `Fixes #<issue-number>` (or `Closes #<issue-number>`) in the PR description so merging the PR automatically closes the issue:

     ```bash
     gh pr create --draft \
       --title "feat(<short-service-name>): generate library" \
       --body "$(cat <<'EOF'
     Generate library for `<proto-path>`.

     Fixes #<issue-number>
     EOF
     )"
     ```

   - **If no issue was referenced**:
     ```bash
     gh pr create --draft \
       --title "feat(<short-service-name>): generate library" \
       --body "Generate library for \`<proto-path>\`."
     ```

3. **Report PR Link**:
   Provide the PR link and status to the user upon completion.
