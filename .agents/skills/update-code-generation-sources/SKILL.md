---
name: update-code-generation-sources
description: >-
  Use this skill to update code generation sources (such as googleapis and discovery proto/API specifications) in google-cloud-swift, regenerate all affected client libraries using librarian, troubleshoot generation issues, validate packages, and open a pull request.
---

# Update Code Generation Sources

This skill guides the agent through updating the code generation source specifications (e.g., `sources.googleapis`, `sources.discovery`, or all sources) in `google-cloud-swift`, regenerating all client libraries via `librarian`, resolving any new dependencies or configuration requirements, validating the generated packages, and creating a pull request.

--------------------------------------------------------------------------------

## Prerequisites and Environment Verification

Before updating sources and regenerating code, verify that all required tools and compilers are installed and meet the version requirements, as detailed in the [Set Up Development Environment Guide](../../../doc/contributor/howto-guide-set-up-development-environment.md):

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
   *Requirement*: `gh` must be authenticated to create pull requests.

--------------------------------------------------------------------------------

## Step-by-Step Workflow

### Step 1: Create a Clean Branch

Ensure the local branch is synchronized with upstream `main` before starting:

```bash
git checkout main
git pull --ff-only upstream main || git pull --ff-only origin main
```

Create a new branch dated with today's date:

```bash
git checkout -b chore-update-shas-circa-$(date +%Y-%m-%d)
```

### Step 2: Retrieve Librarian Version

Retrieve the current librarian version configured for the repository:

```bash
V=$(go run github.com/googleapis/librarian/cmd/librarian@latest config get version)
```

### Step 3: Update Source Specifications

Follow the instructions in [Generated Code Maintenance](../../../doc/contributor/howto-guide-generated-code-maintenance.md):

- **Standard Update (Discovery and GoogleAPIs)**:
  ```bash
  go run github.com/googleapis/librarian/cmd/librarian@${V} update sources.discovery
  go run github.com/googleapis/librarian/cmd/librarian@${V} update sources.googleapis
  ```

- **Alternative (All Sources)**:
  To update all sources at once (including `showcase` and `conformance`/`protobuf`):
  ```bash
  go run github.com/googleapis/librarian/cmd/librarian@${V} update --all
  ```

### Step 4: Regenerate All Client Libraries

Regenerate all generated libraries using the updated proto definitions:

```bash
go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
```

Run `librarian tidy` to format and sort [`librarian.yaml`](../../../librarian.yaml):

```bash
go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
```

### Step 5: Handle Common Generation Errors (Troubleshooting)

Updating sources to newer commit SHAs may introduce new protos, messages, or cross-package dependencies. If `librarian generate --all` fails, consult the [Librarian Playbook](../../../doc/contributor/librarian-playbook.md):

1. **Package Not Found in `ApiPackages`**:
   - *Symptom*:
     ```text
     librarian: generate library "<library-name>" (swift): package "<protobuf.package.name>" not found in ApiPackages
     ```
   - *Context*: Updated proto files may now reference messages or enums from other API packages not yet mapped in `librarian.yaml`.
   - *Resolution*: Add the missing package under `default -> swift -> dependencies` in [`librarian.yaml`](../../../librarian.yaml):
     ```yaml
     default:
       swift:
         dependencies:
           - name: <DependencyModuleName>
             path: generated/<dependency-package-directory>
             api_package: <protobuf.package.name>
     ```
   - Run `go run github.com/googleapis/librarian/cmd/librarian@${V} tidy` and re-run `go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all`.

2. **PascalCase / Module Name Override Required**:
   - *Symptom*:
     ```text
     librarian: generate library "<library-name>": default library name for <proto-path> needs override.
     Other languages with PascalCase style deviate from the default name for this library...
     ```
   - *Resolution*: Add `library_name_override` under the specific library entry in [`librarian.yaml`](../../../librarian.yaml):
     ```yaml
       - name: <library-name>
         version: 0.0.0-preview
         copyright_year: "2026"
         swift:
           library_name_override: <PascalCaseName>
     ```
   - Run `go run github.com/googleapis/librarian/cmd/librarian@${V} tidy` and re-run `go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all`.

### Step 6: Validate the Changes

1. **Review Changed Files**:
   ```bash
   git status
   git diff --stat
   ```
   Ensure that only [`librarian.yaml`](../../../librarian.yaml) and files in `generated/` are modified.

2. **Build and Test Sample/Key Generated Packages**:
   Run the CI check script for generated packages:
   ```bash
   ./ci/generated.sh
   ```
   Or run targeted tests on packages with significant changes:
   ```bash
   swift test --package-path generated/<modified-library-name>
   ```

3. **Lint Code**:
   ```bash
   ./ci/lint.sh
   ```
   Or lint specific modified packages:
   ```bash
   swift-format lint -r generated/<modified-library-name>/Sources generated/<modified-library-name>/Tests
   ```

> [!IMPORTANT]
> **Never manually edit code inside `generated/`**. All code in `generated/` is generated and managed by `librarian`.

### Step 7: Commit the Changes

Follow the Conventional Commits format:

```bash
git add .
git commit -m "chore: update discovery and googleapis SHA circa $(date +%Y-%m-%d)"
```

### Step 8: Push and Create a Draft Pull Request

1. **Push Branch to Origin**:
   ```bash
   git push -u origin chore-update-shas-circa-$(date +%Y-%m-%d)
   ```

2. **Create Draft Pull Request with GitHub CLI (`gh`)**:
   Always open the pull request in **draft mode** using `--draft`.

   - **If a tracking GitHub issue was referenced**:
     ```bash
     gh pr create --draft \
       --title "chore: update discovery and googleapis SHA circa $(date +%Y-%m-%d)" \
       --body "$(cat <<'EOF'
     Update code generation sources (`sources.discovery` and `sources.googleapis`) and regenerate all client libraries.

     Fixes #<issue-number>
     EOF
     )"
     ```

   - **Standard PR**:
     ```bash
     gh pr create --draft \
       --title "chore: update discovery and googleapis SHA circa $(date +%Y-%m-%d)" \
       --body "Update code generation sources (\`sources.discovery\` and \`sources.googleapis\`) and regenerate all client libraries."
     ```

3. **Report PR Link**:
   Provide the PR link and summary to the user upon completion.
