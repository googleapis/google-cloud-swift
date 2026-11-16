# AI Assistant Guide for `google-cloud-swift`

This document outlines critical rules, coding standards, and workflow practices for contributing to this project. Please strictly adhere to these instructions.

## Code Style and Conventions

- **Google Swift Style**: This project follows the naming conventions and general practices defined in the [Google Swift Style Guide](https://google.github.io/swift/).
- **Swift Formatter**: Code formatting is verified and enforced via `swift-format`. **When the style guide and the formatter disagree, always prefer the output from `swift-format`.**
- **Import Modifiers**:
  - Prefer plain `import <Module>`. The project targets Swift 6 with `InternalImportsByDefault`, making `internal import` redundant.
  - Only use `public import <Module>` when types from `<Module>` are part of the target's public API surface or `@inlinable` code. Unused `public import` statements fail compilation under `-warnings-as-errors`.
- **Access Control and Testing**:
  - Do not elevate visibility of types, functions, or properties (such as using `package`, `public`, or `@_spi`) solely to facilitate unit testing.
  - Keep internal implementation details `internal` (default access) and use `@testable import <Target>` in test files.
- **Hand-written Public APIs**: See [Hand-written Packages](#hand-written-packages) below.
- **Error Types**:
  - Error types that are expected to be surfaced to or handled by users must conform to both `CustomStringConvertible` and `CustomDebugStringConvertible`.
  - When an uncaught error escapes `@main`, the Swift runtime formats it using `String(reflecting: error)` (`CustomDebugStringConvertible.debugDescription`). Ensure `debugDescription` includes both the structured type/case context and the human-readable explanation so top-level crashes remain actionable.

## Hand-written Packages

These rules apply to **new public APIs** in hand-written packages (e.g.
`pkgs/swift-google-cloud-storage`, `pkgs/swift-google-cloud-datastore`). Some
existing APIs predate them; do not copy those exceptions, and do not change
existing public APIs only to conform. [ARCHITECTURE.md](ARCHITECTURE.md) is
binding, in particular "No client-side validation", "Separate namespace for
fields vs. options", and "Mocking and testing". The full rules, with rationale
and examples, are in
[howto-guide-handwritten-client-api.md](doc/contributor/howto-guide-handwritten-client-api.md).
Read it before designing or reviewing a public API.

Rules that are hard to fix after a release:

- Applications implement the service protocols as mocks, so every requirement
  signature is frozen. Requirements that wrap RPCs return named structs, even if
  the response is empty or has a single field today (never tuples, `Void`, or a
  bare model type that discards server data), end with an operation-specific
  options struct (no positional knobs or `Bool` flags), and have a default
  implementation with the same semantics as the real client.
- Do not validate service limits on the client, and never validate data decoded
  from the service. Value-type initializers do not `throw` to enforce limits.
- No `Codable` on hand-written public types unless the encoding is canonical
  ProtoJSON.
- Veneer retry loops use `GoogleGax.RetryPolicy` and `BackoffPolicy`, not
  `maxAttempts: Int`.
- `AsyncSequence` and other streamed results can be mocked *and* wrapped by a
  forwarding decorator using only public API.
- Use the minimum concurrency annotations (`@Sendable`, `T: Sendable`) on
  closure parameters of protocol requirements.
- Every public error case is thrown somewhere; document which failures are
  `GoogleGax.RequestError` and which are the package error type.
- Macro expansions call only `_`-prefixed helpers marked
  `@_documentation(visibility: internal)`. Macros should be in a separate
  package; if they are in the same package, the design document must explain
  why, and they must be in a separate product.
- Use uniformly cased acronyms (`projectID`, `allocateIDs()`), `Int` for counts
  and limits, and a single level of options (no `options.request.request`).
- Logging metadata keys match the generated `<Service>+Logging` layer, and
  `rpc.method` always names a real RPC.

Required checks, in the same pull request as the new API:

- For every option field, a test asserting the request the server receives.
- A test with plain `import` (never `@testable`) that implements a mock and a
  forwarding decorator of every public protocol, including streamed results.
- For multi-RPC operations, tests for a transient failure that recovers, for
  retries running out, and for the behavior after the terminal error, including
  the error type. Every public error case is produced by some test.
- Docstrings on every public symbol, including protocol conformance members;
  `@Snippet`s that call the symbol they document; DocC articles on mocking,
  error handling, retries, and observability.
- If the package has a design document in `doc/design/`, update it when the
  implementation diverges.
- Comply with `.strictMemorySafety()` across library code, `Snippets/`, and
  `Tests/`: protect mutable state using `Synchronization.Mutex` inside `final class`
  or `StateBox` reference wrappers (never `@unchecked Sendable`), and avoid
  `withUnsafeCurrentTask` in tests.

## Dependencies and Local Development

The packages in this repository default to using release dependencies. For local
development always set the `GOOGLE_CLOUD_SWIFT_LOCAL_DEPS` environment to
`true`.

A side-effect of using this environment variable is that `Packages.resolved`
changes and removes references to remote dependencies. Do not commit these
changes.

Use the following command to test a single package:

```bash
env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift test -Xswiftc -warnings-as-errors --package-path pkgs/${package_name}
```

Running `./ci/test.sh` automatically resolves dependencies using local working directories for all packages in the repository via `GOOGLE_CLOUD_SWIFT_LOCAL_DEPS` configured in `ci/build-flags.sh`.

## Code Generation (`generated/`)

- **Librarian Generated Code**: All contents inside the `generated/` directory are automatically generated by the `librarian` tool.
  - **NEVER manually edit the code in `generated/`**.
  - For maintenance instructions and regeneration commands, consult `doc/contributor/howto-guide-generated-code-maintenance.md`.
- **Protobuf and Model Conversions**:
  - When protobuf messages or data model conversions are required, add them to `librarian.yaml` under the appropriate library with module types `swift-protobuf` or `convert-swift`, then run `librarian generate`.
  - Do not handwrite protobuf messages or invoke `protoc` manually.
- **Deprecation Warnings**:
  - The generated code carries the deprecations from the source specification, and must still read, write and convert those declarations. The generator emits `#if hasAttribute(diagnose)` / `@diagnose(DeprecatedDeclaration, as: ignored)` blocks to silence the resulting warnings.
  - `@diagnose` requires Swift 6.4 (SE-0522). The build scripts demote the diagnostic with `-Xswiftc -Wwarning -Xswiftc DeprecatedDeclaration` only for older toolchains, via `swift_supports_diagnose` in `ci/swift-version.sh`.
  - **Do not make that demotion unconditional**. On Swift 6.4 and later it would also hide genuine use of deprecated APIs in the hand-written code.

## Testing Strategy

- **Swift Testing Framework**: Always use `import Testing` for tests. Never use `import XCTest`.
- **Test Organization**: Group all the unit tests for a class or struct under a `@Suite struct` structure, named for the struct or class under test.
- **Targeted Testing**: Prefer testing packages individually instead of the entire monorepo tree to save build time. Use CI compiler flags to catch warnings early:
  ```bash
  env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift test -Xswiftc -warnings-as-errors --package-path pkgs/${package_name}
  ```
  If testing changes to `swift-google-auth` or `swift-google-wkt`, ensure `GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true` is set or run `ci/test.sh`.
- **Global Validation**: To perform full validation on all packages (formatting, linting, test coverage), examine the workflow scripts in the `ci/` directory:
  ```bash
  ./ci/lint.sh pr
  ./ci/test.sh
  ```
- **Integration Tests**: Integration tests require explicit Google Cloud credentials and are restricted behind traits. Use:
  ```bash
  env GOOGLE_CLOUD_PROJECT="<your-project>" swift test
  ```
