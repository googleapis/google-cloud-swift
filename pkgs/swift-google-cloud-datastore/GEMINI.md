# AI Assistant Guide for `pkgs/swift-google-cloud-datastore`

This document defines conventions, design principles, and guidelines for maintaining the `pkgs/swift-google-cloud-datastore` package.

## Development Guidelines

- **Adherence to Repository Standards**: All development in this package must strictly adhere to the top-level repository guidelines in [`../../GEMINI.md`](../../GEMINI.md) and the design specification in [`../../doc/design/datastore.md`](../../doc/design/datastore.md).
- **Local Dependencies**: Always set `GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true` during local development so dependencies resolve to local working packages rather than remote release tags.
- **Compilation, Testing, and Linting Commands**:
  - **Compile**:
    ```bash
    env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift build --build-tests -Xswiftc -warnings-as-errors -Xcc --gcc-toolchain=/usr -Xcxx --gcc-toolchain=/usr --package-path pkgs/swift-google-cloud-datastore
    ```
  - **Unit Tests**:
    ```bash
    env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift test -Xswiftc -warnings-as-errors -Xcc --gcc-toolchain=/usr -Xcxx --gcc-toolchain=/usr --package-path pkgs/swift-google-cloud-datastore
    ```
  - **Lint**:
    ```bash
    swift-format lint --strict -r pkgs/swift-google-cloud-datastore/Sources pkgs/swift-google-cloud-datastore/Tests
    ```
  - **Format Code**:
    ```bash
    swift-format format -i -r pkgs/swift-google-cloud-datastore/Sources pkgs/swift-google-cloud-datastore/Tests
    ```
