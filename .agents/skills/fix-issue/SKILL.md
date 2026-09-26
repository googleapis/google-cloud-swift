---
name: fix-issue
description: >-
  Use this skill to prepare a plan and implement a fix for an issue in google-cloud-swift
  (e.g., https://github.com/googleapis/google-cloud-swift/issues/NNNN or issue number NNNN).
  Enforces worktree isolation, adherence to GEMINI.md in google-cloud-swift and AGENTS.md in librarian,
  subagent PR review for librarian changes, a two-commit rule when code generator changes are involved,
  and commit titles strictly under 50 characters.
---

# Fix Issue Workflow for `google-cloud-swift`

This skill guides the agent through investigating, planning, and implementing fixes for issues in [`google-cloud-swift`](https://github.com/googleapis/google-cloud-swift).

It enforces:
1. **Worktree & Branch Isolation**: Always work in a dedicated worktree and branch.
2. **Project Guidelines**:
   - Follow [`GEMINI.md`](../../../GEMINI.md) in `google-cloud-swift`.
   - Follow `AGENTS.md` in `librarian` whenever generator changes are involved.
3. **Subagent Code Review**: Use a subagent to run the `review-pr` skill on `librarian` changes.
4. **Two-Commit Rule for Librarian Changes**: Split generator output and Swift tests/edits into separate commits.
5. **Commit Title Constraint**: Keep all commit titles strictly **under 50 characters**.

--------------------------------------------------------------------------------

## Workflow Steps

### Step 1: Parse and Inspect the Issue

Extract the issue number (`<NNNN>`) from the user prompt or issue URL:
```bash
# Example: https://github.com/googleapis/google-cloud-swift/issues/1234 -> 1234
ISSUE_NUM="<NNNN>"
```

Inspect the issue using GitHub CLI:
```bash
gh issue view "${ISSUE_NUM}" --repo googleapis/google-cloud-swift --json number,title,body,labels,comments
```

Identify:
- The affected component or library (e.g. `storage`, `compute`, `auth`, `gax`).
- The root cause: Is it a bug in the code generator (`librarian`), or in hand-written code/tests in `google-cloud-swift`?
- Acceptance criteria and reproducer cases.

---

### Step 2: Worktree and Branch Setup in `google-cloud-swift`

Always perform work in a dedicated worktree and branch.

1. **Locate or Determine Worktree Location**:
   - Team members organize worktrees differently. Check in this order:
     1. Sibling of `main`: `../fix-issue-${ISSUE_NUM}` (relative to `main`).
     2. Subdirectory in `worktrees/`: `../worktrees/fix-issue-${ISSUE_NUM}`.
     3. If neither exists, check the parent directory layout to match existing patterns, or create it as a sibling of `main` (`../fix-issue-${ISSUE_NUM}`). If ambiguous, ask the user.

2. **Create the Worktree and Branch**:
   ```bash
   BRANCH_NAME="fix-issue-${ISSUE_NUM}"
   WORKTREE_PATH="../${BRANCH_NAME}"

   # Fetch latest main
   git -C main fetch upstream main || git -C main fetch origin main

   # Create worktree
   git -C main worktree add -b "${BRANCH_NAME}" "${WORKTREE_PATH}" upstream/main
   ```

3. **Switch Context**: Perform all subsequent commands and modifications inside the newly created worktree.

---

### Step 3: Research and Formulate the Implementation Plan (`/plan`)

Before modifying code, research the problem and write an implementation plan artifact adhering to the Jetski `/plan` standard.

#### Key Guidelines to Follow:
- **`google-cloud-swift` Rules**: Strictly follow [`GEMINI.md`](../../../GEMINI.md):
  - Testing framework: Always `import Testing` with `@Suite struct` (never `import XCTest`).
  - Formatting: Code must pass `swift-format` and `./ci/lint.sh pr`.
  - Access control: Do not elevate visibility (e.g. `public`, `package`) solely for unit tests; use `@testable import`.
  - Dependencies: If modifying packages locally, use `GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift test` or `./ci/test.sh`.
- **`librarian` Rules**: If the issue originates in the code generator, consult and follow `AGENTS.md` in `librarian`.

#### Check if Librarian Changes are Required:
- If code generator modifications are needed:
  1. Locate or create a worktree in `librarian` following the same convention (sibling of `main` or `worktrees/fix-issue-${ISSUE_NUM}`).
  2. Clearly document both the `librarian` changes and the `google-cloud-swift` changes in the plan.
  3. Note the two-commit structure and subagent review requirement in the plan.
- Create the plan artifact with `request_feedback: true` and obtain user approval before proceeding to implementation.

---

### Step 4: Implementation and Verification

#### Scenario A: Changes to `librarian` are Required

1. **Implement in `librarian` Worktree**:
   - Make the necessary changes in the generator following `librarian/AGENTS.md` and Go conventions.
   - Run Go unit tests:
     ```bash
     go test ./...
     ```

2. **Test Generation Locally in `google-cloud-swift`**:
   - Test generating code with the local librarian binary directly against `google-cloud-swift`:
     ```bash
     go run <path-to-librarian-worktree>/cmd/librarian generate --library <library-name>
     ```
   - Verify that the generated code fixes the issue and passes local formatting and build.

3. **Subagent Code Review for `librarian`**:
   - Ask a subagent via `invoke_subagent` to run the `review-pr` skill on the `librarian` worktree:
     ```json
     {
       "TypeName": "self",
       "Role": "Librarian PR Reviewer",
       "Prompt": "Run the review-pr skill in <path-to-librarian-worktree> to review the local changes for issue <NNNN> against project conventions."
     }
     ```
   - Address any actionable feedback identified by the subagent review.

4. **Coordinate PRs and Update `librarian.yaml`**:
   - Open a PR in `googleapis/librarian` (or wait for review/merge).
   - Once the target version or commit is available, update `librarian.yaml` and regenerate:
     ```bash
     go run github.com/googleapis/librarian/cmd/librarian@${V} config set version ${V}
     go run github.com/googleapis/librarian/cmd/librarian@${V} generate --all
     go run github.com/googleapis/librarian/cmd/librarian@${V} tidy
     ```

5. **CRITICAL: The Two-Commit Rule in `google-cloud-swift`**:
   Split the changes into **two separate commits**:
   - **Commit 1: Automatic Librarian Changes**:
     - Stage only the generated code (`generated/`) and `librarian.yaml`.
     - Commit title **MUST be under 50 characters**.
     - Example: `feat(generator): update generated code for #1234`
   - **Commit 2: Swift Hand-written Code & Tests**:
     - Stage tests, documentation, or other manual modifications in `google-cloud-swift`.
     - Commit title **MUST be under 50 characters**.
     - Example: `test(storage): add tests for #1234`

---

#### Scenario B: Pure `google-cloud-swift` Changes (No `librarian` Changes)

1. **Implement and Test in `google-cloud-swift`**:
   - Implement the fix in the appropriate package under `pkgs/` or `Sources/`.
   - Add unit tests under `Tests/` using Swift Testing (`import Testing`, `@Suite struct`).
   - Run targeted package tests:
     ```bash
     swift test -Xswiftc -warnings-as-errors --package-path pkgs/<package_name>
     ```

2. **Commit Changes**:
   - Use Conventional Commits (`fix(pkg): ...`, `test(pkg): ...`).
   - Commit title **MUST be under 50 characters**.

---

### Step 5: Pre-PR Validation Checklist

Before presenting the work or opening a PR, verify:

1. **Commit Title Length Check**:
   Confirm all commit titles on the branch are strictly under 50 characters:
   ```bash
   git log origin/main..HEAD --format="%s" | while read -r title; do
     len=${#title}
     if [ "$len" -gt 50 ]; then
       echo "ERROR: Commit title exceeds 50 chars ($len): $title"
     else
       echo "OK ($len chars): $title"
     fi
   done
   ```

2. **Lint and Format Check**:
   ```bash
   ./ci/lint.sh pr
   ```

3. **Package Tests**:
   ```bash
   ./ci/test.sh
   # Or targeted: GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true -Xswiftc -warnings-as-errors --package-path pkgs/<pkg>
   ```

4. **User Confirmation Before Push**:
   - Never automatically push to remote or open a PR without asking the user.
   - Summarize the commits and validation results, and ask the user if they want to push and open a PR.
