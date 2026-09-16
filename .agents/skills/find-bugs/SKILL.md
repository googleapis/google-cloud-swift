---
name: find-bugs
description: >-
  Use this skill to review code, search for bugs, audit PRs or code changes,
  and identify new defects in the codebase while avoiding duplicates and overly verbose descriptions.
---

# Find Bugs

This skill guides the agent through reviews of the code with the intent of identifying new, unknown bugs without making fixes.

--------------------------------------------------------------------------------

## Prerequisites and Environment Verification

1. Before starting, ensure the code compiles and passes baseline checks. Refer to [GEMINI.md](../../GEMINI.md) for package build and test instructions:
   ```bash
   swift test --package-path pkgs/<package_name>
   ```

2. Verify that the GitHub CLI (`gh`) is available for deduplication searches:
   ```bash
   gh auth status
   ```

--------------------------------------------------------------------------------

## Scope and Target Identification

Determine the target scope based on user instructions:
- **PR or Branch Review**: Inspect the diff against `main` (e.g., `git diff main...HEAD` or `gh pr diff <PR>`).
- **Uncommitted Changes**: Inspect working directory diffs (`git diff`).
- **Specific Package / Directory**: Focus on handwritten code packages under `pkgs/` (e.g., `pkgs/swift-google-cloud-storage`).
- **Generated Code**: Avoid reporting issues in `generated/` unless the issue clearly originates from generation templates or generator logic in `librarian`.

--------------------------------------------------------------------------------

## Bug Identification Guidelines

Focus on genuine defects rather than code style or linter warnings (which are caught by formatters/linters):
- **Logic & Correctness**: Off-by-one errors, inverted conditions, improper nil/optional handling, unhandled error cases.
- **Concurrency & State**: Race conditions, data races, deadlocks, incorrect async/await task cancellations, unprotected mutable state across concurrency boundaries.
- **Resource Leaks & Lifecycle**: Unclosed connections, streams, or buffers; missing cleanup on early returns or error paths.
- **API Contract Violations**: Incorrect HTTP status handling, header formatting, or parameter encoding.

--------------------------------------------------------------------------------

## Deduplication Workflow

Before logging a bug, verify that it has not already been acknowledged or reported:

1. **Inline Comments**: Check if nearby lines contain `TODO`, `FIXME`, or comments explaining deliberate design trade-offs.
2. **GitHub Issues (Open & Closed)**: Search repository issues (including closed ones, as they may document why an issue is invalid or working as intended):
   ```bash
   gh issue list --state all --search "<keywords or symbol names>"
   ```
3. If an existing open or closed issue matches, skip reporting or note the existing issue number.

--------------------------------------------------------------------------------

## Bug Report Format

Do not modify the codebase or apply fixes. Generate a separate Markdown report file for each bug found in the scratch directory (e.g., `bug-<short-name>.md`) with the following structure:

```markdown
# [Short Descriptive Bug Name]

## Location
- [path/to/file.swift:L10-L25](file:///path/to/file.swift#L10-L25)

## Description
[Max 2 paragraphs explaining the defect, trigger conditions, and impact. Provide sufficient detail so a human can confirm or deny the bug directly from the description and code reference.]

## Steps to Reproduce / Verification
[Brief explanation of how to reproduce or verify the bug via unit test or code trace.]
```
