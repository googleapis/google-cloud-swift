# AI Assistant Guide for `pkgs/swift-google-gax`

This document defines conventions, architectural boundaries, and testing guidelines for maintaining `pkgs/swift-google-gax` (`GoogleGax`).

## Development Guidelines

- **Adherence to Repository Standards**: All development in this package must strictly adhere to the top-level repository guidelines in [`../../AGENTS.md`](../../AGENTS.md) and [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md), including `swift-format` precedence, import modifiers (`InternalImportsByDefault`, `MemberImportVisibility`), `.strictMemorySafety()`, and Swift Testing (`import Testing`, `@Suite struct`).
- **Synchronization Primitives**: Prefer Swift 6 standard-library synchronization primitives from `import Synchronization` (`Mutex<T>`, `Atomic<T>`) or Swift `actor`s for thread-safe mutable state inside `Sendable` reference types. Never introduce `NIOConcurrencyHelpers` (`NIOLockedValueBox<T>`, `NIOLock`), `NSLock`, `os_unfair_lock`, `DispatchQueue` locks, or `@unchecked Sendable` wrappers.
- **Public API Boundaries**: Every cross-package runtime hook intended solely for generated or hand-written Google Cloud client libraries must be gated behind `@_spi(GoogleCloudInternal)` and prefixed with `_` (such as `_Host`, `_HTTPClient`, `_ApiClientHeader`, `_RoutingMatcher`, and `_CRC32C`), following [`../../doc/public-api.md`](../../doc/public-api.md).
- **Minimal Dependency Footprint**: Keep `GoogleGax` free of gRPC (`grpc-swift-2`) and Protobuf (`SwiftProtobuf`) dependencies so HTTP/REST clients do not pull the gRPC stack into their Swift Package Manager dependency graph.
- **Local Dependencies**: Always set `GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true` during local development so dependencies resolve to local working packages rather than remote release tags.
- **Compilation, Testing, and Linting Commands**:
  - **Compile**:
    ```bash
    env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift build --build-tests -Xswiftc -warnings-as-errors --package-path pkgs/swift-google-gax
    ```
  - **Unit Tests**:
    ```bash
    env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift test -Xswiftc -warnings-as-errors --package-path pkgs/swift-google-gax
    ```
  - **Lint**:
    ```bash
    swift-format lint --strict -r pkgs/swift-google-gax/Sources pkgs/swift-google-gax/Tests
    ```
  - **Format Code**:
    ```bash
    swift-format format -i -r pkgs/swift-google-gax/Sources pkgs/swift-google-gax/Tests
    ```

---

## Strict Service-Agnostic Boundary

`GoogleGax` is shared by every generated and hand-written Google Cloud client library in the repository. It **must not** contain any service-specific logic or knowledge.

1. **No Service Identifiers or Endpoints**:
   - **NEVER** hardcode service-specific default endpoints or hostnames (such as `"pubsub.googleapis.com"` or `"storage.googleapis.com"`).
   - **NEVER** hardcode service-specific environment variable names (such as `"PUBSUB_EMULATOR_HOST"` or `"STORAGE_EMULATOR_HOST"`). Only universal SDK-wide environment variables (such as `GOOGLE_CLOUD_UNIVERSE_DOMAIN`) belong in `GoogleGax`.
   - **NEVER** add service-specific HTTP headers, error-code special cases, or retry/idempotency policies inside `GoogleGax`. Service-specific retry policies, idempotency rules, and emulator variable names live in each service's own package or generation configuration.
2. **Caller-Parameterized Hooks Pattern**:
   - When a client initialization or transport behavior is shared across services—such as resolving an emulator endpoint from an environment variable, normalizing bare `host:port` values to plaintext `http://`, or defaulting to `.anonymous` credentials when an emulator environment variable is active—expose a generic hook parameter whose service-specific value is supplied by the caller.
   - For example, `_Host.resolveEmulatorEndpoint(endpoint:emulatorEnvironmentVariable:environment:)` and `_HTTPClient.init(from:withDefaultEndpoint:clientHeader:emulatorEnvironmentVariable:)` accept an optional `emulatorEnvironmentVariable: String? = nil` provided by the service client (`"PUBSUB_EMULATOR_HOST"` or `"STORAGE_EMULATOR_HOST"`), leaving `GoogleGax` unaware of which service is calling it.
3. **Configuration Precedence**:
   - Explicit `ClientOptions` overrides (`endpoint`, `credentials`, `universeDomain`) always take precedence over environment variables and defaults.
   - Credential resolution against an emulator endpoint must still allow explicit `ClientOptions.credentials` to override the emulator `.anonymous` default without affecting endpoint routing.

---

## Testing Requirements

- **No Process-Global Environment Mutation**: Helper methods and internal initializers that inspect environment variables (such as `_Host.resolveUniverseDomain`, `_Host.resolveEmulatorEndpoint`, and `_HTTPClient.init`) must take an injectable `environment: [String: String]` parameter, with public/SPI convenience overloads defaulting to `ProcessInfo.processInfo.environment`. Never call `setenv` or `unsetenv` in parallel Swift Testing suites.
- **Synthetic Test Fixtures**: Unit tests in `pkgs/swift-google-gax/Tests/` must use generic synthetic endpoints and environment variable names (such as `"https://example.googleapis.com"` and `"EXAMPLE_EMULATOR_HOST"`). Never name test files, suites, or fixtures after specific Google Cloud services (such as `PubSubEmulatorTests`).
- **Parameterized Tests**: Prefer parameterized `@Test(arguments: ...)` for input variations that share a parameter shape, and separate single-purpose `@Test` functions for distinct behaviors.
