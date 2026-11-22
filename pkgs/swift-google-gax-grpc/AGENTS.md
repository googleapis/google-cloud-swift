# AI Assistant Guide for `pkgs/swift-google-gax-grpc`

This document defines conventions, architectural boundaries, and testing guidelines for maintaining `pkgs/swift-google-gax-grpc` (`GoogleGaxGRPC`).

## Development Guidelines

- **Adherence to Repository Standards**: All development in this package must strictly adhere to [`../../AGENTS.md`](../../AGENTS.md), [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md), and the shared GAX boundary rules in [`../swift-google-gax/AGENTS.md`](../swift-google-gax/AGENTS.md).
- **Synchronization Primitives**: Prefer Swift 6 standard-library synchronization primitives from `import Synchronization` (`Mutex<T>`, `Atomic<T>`) or Swift `actor`s. Never introduce `NIOConcurrencyHelpers` (`NIOLockedValueBox<T>`, `NIOLock`), `NSLock`, or `@unchecked Sendable` wrappers, and do not add direct `swift-nio` product dependencies for synchronization or byte buffers.
- **Public API Boundaries**: Cross-package runtime types intended for generated or hand-written gRPC clients (`_GRPCClient`, `_RoutingMatcher`, `_RoutingSegment`) must be gated behind `@_spi(GoogleCloudInternal)` and prefixed with `_`, following [`../../doc/public-api.md`](../../doc/public-api.md).
- **Delegation to `GoogleGax`**: Delegate shared endpoint normalization, universe-domain resolution, emulator environment-variable resolution, and authority calculation to `GoogleGax._Host` rather than duplicating logic in `GoogleGaxGRPC`.
- **Local Dependencies**: Always set `GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true` during local development so dependencies resolve to local working packages rather than remote release tags.
- **Compilation, Testing, and Linting Commands**:
  - **Compile**:
    ```bash
    env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift build --build-tests -Xswiftc -warnings-as-errors --package-path pkgs/swift-google-gax-grpc
    ```
  - **Unit Tests**:
    ```bash
    env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift test -Xswiftc -warnings-as-errors --package-path pkgs/swift-google-gax-grpc
    ```
    *(Note: On gLinux workstations, add `-Xcc --gcc-toolchain=/usr -Xcxx --gcc-toolchain=/usr` to avoid `'memory' file not found` errors when compiling C++ BoringSSL dependencies in `grpc-swift-nio-transport`.)*
  - **Lint**:
    ```bash
    swift-format lint --strict -r pkgs/swift-google-gax-grpc/Sources pkgs/swift-google-gax-grpc/Tests
    ```
  - **Format Code**:
    ```bash
    swift-format format -i -r pkgs/swift-google-gax-grpc/Sources pkgs/swift-google-gax-grpc/Tests
    ```

---

## Strict Service-Agnostic Boundary

Like `GoogleGax`, `GoogleGaxGRPC` is shared transport infrastructure across all gRPC-based Google Cloud libraries:

- **No Service-Specific Logic**: Never hardcode service hostnames, service emulator environment variable names, service-specific message sizes, or service-specific metadata headers inside `GoogleGaxGRPC`.
- **Caller-Parameterized Hooks**: Expose customization via optional caller-supplied parameters on `_GRPCClient` (such as `emulatorEnvironmentVariable: String? = nil`) forwarded to `GoogleGax._Host`, while preserving `ClientOptions` override precedence (`ClientOptions.endpoint` beats emulator env vars; explicit `ClientOptions.credentials` beats `.anonymous`).
- **Injectable Environment in Tests**: Internal `_GRPCClient` initializers must accept `environment: [String: String]` for hermetic testing without `setenv`. Unit tests in `pkgs/swift-google-gax-grpc/Tests/` must use generic synthetic endpoints and environment variable names (such as `"https://example.googleapis.com"` and `"EXAMPLE_EMULATOR_HOST"`), never service-specific names.
