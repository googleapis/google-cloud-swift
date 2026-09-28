# AI Assistant Guide for `pkgs/swift-google-cloud-storage`

This document defines conventions, design principles, and guidelines for maintaining the `pkgs/swift-google-cloud-storage` package, with specific focus on custom idempotency hooks for generated RPC types.

## Development Guidelines

- **Adherence to Repository Standards**: All development in this package must strictly adhere to the top-level repository guidelines in [`../../GEMINI.md`](../../GEMINI.md), including style conventions (`swift-format` precedence), import rules, access control, and testing practices (`import Testing`, `@Suite struct`).
- **Local Dependencies**: Always set `GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true` during local development so dependencies resolve to local working packages rather than remote release tags.
- **Compilation, Testing, and Linting Commands**:
  - **Compile**:
    ```bash
    env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift build --build-tests -Xswiftc -warnings-as-errors --package-path pkgs/swift-google-cloud-storage
    ```
  - **Unit Tests**:
    ```bash
    env GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=true swift test -Xswiftc -warnings-as-errors --package-path pkgs/swift-google-cloud-storage
    ```
    *(Note: On gLinux workstations, add `-Xcc --gcc-toolchain=/usr -Xcxx --gcc-toolchain=/usr` to avoid `'memory' file not found` errors when compiling C++ BoringSSL dependencies).*
  - **Lint**:
    ```bash
    swift-format lint -r pkgs/swift-google-cloud-storage/Sources pkgs/swift-google-cloud-storage/Tests
    ```
  - **Format Code**:
    ```bash
    swift-format format -i -r pkgs/swift-google-cloud-storage/Sources pkgs/swift-google-cloud-storage/Tests
    ```

---

## Storage Idempotency Hooks

### Overview

In `librarian.yaml`, code generation for `google-cloud-storage` configures:

```yaml
idempotency_hook: resolveIdempotency
```

This directive instructs the generator to inject custom idempotency resolution at the beginning of each generated RPC method in `Sources/GoogleCloudStorage/generated/Storage/Storage+Retry.swift`:

```swift
let options = request.resolveIdempotency(options: options)
```

Consequently, every request type handled by the generated `Storage` client must provide an extension conforming to:

```swift
extension <RequestType> {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions
}
```

These extensions reside in `Sources/GoogleCloudStorage/StorageIdempotency.swift`.

---

## Idempotency Rules

When implementing or updating `resolveIdempotency(options:)` for a request type, follow these rules:

1. **Read-Only Operations**:
   - The request is idempotent by default.
   - Use `resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)`.
   - Examples: `GetBucketRequest`, `ListBucketsRequest`, `GetObjectRequest`, `ListObjectsRequest`.

2. **Metadata Modifications (Buckets and Objects)**:
   - The operation is idempotent **if and only if** there are preconditions on the metageneration (e.g., `self.ifMetagenerationMatch != nil` or `self.ifMetagenerationMatch > 0`).
   - For objects, specifying a generation match (`self.ifGenerationMatch != nil`) also targets a specific generation.
   - Use `isMutating: true`.
   - Examples: `UpdateBucketRequest`, `LockBucketRetentionPolicyRequest`, `UpdateObjectRequest`.

3. **Delete Operations**:
   - Operations that delete objects, buckets, or other resources are idempotent **if and only if** there are preconditions on the generation or they affect a single, specific generation.
   - For buckets: `self.ifMetagenerationMatch != nil`.
   - For objects: `self.generation != 0 || self.ifGenerationMatch != nil`.
   - Use `isMutating: true`.
   - Examples: `DeleteBucketRequest`, `DeleteObjectRequest`.

4. **Resource Creation and Transformations**:
   - `CreateBucketRequest`: Idempotent by default (`isIdempotent: true, isMutating: true`).
   - `ComposeObjectRequest` & `RewriteObjectRequest`: Idempotent if generation match precondition is present (`self.ifGenerationMatch != nil`).
   - `MoveObjectRequest`: Idempotent only when preconditions are set on both source and destination (`self.ifGenerationMatch != nil && self.ifSourceGenerationMatch != nil`).
   - `RestoreObjectRequest`: Idempotent if generation or metageneration match is present (`self.ifGenerationMatch != nil || self.ifMetagenerationMatch != nil`).

5. **Exclusion of the `etag` Field**:
   - **The `etag` field is not useful for idempotency determinations in Google Cloud Storage**.
   - **Never** use `ifEtagMatch` or `ifEtagNotMatch` to determine whether an operation is idempotent.

---

## Implementation Pattern

Idempotency resolution is centralized through the internal helper function in `Sources/GoogleCloudStorage/StorageIdempotency.swift`:

```swift
package let idempotencyToken = "x-goog-gcs-idempotency-token"

func resolveStorageIdempotency(
  isIdempotent: Bool,
  isMutating: Bool,
  options: GoogleGax.RequestOptions
) -> GoogleGax.RequestOptions {
  var options = options
  let effectiveIdempotency = options.idempotency ?? isIdempotent
  options.idempotency = effectiveIdempotency
  if isMutating && effectiveIdempotency {
    if options.headers[idempotencyToken] == nil {
      options.headers[idempotencyToken] = UUID().uuidString
    }
  }
  return options
}
```

Key behaviors:
- **Caller Overrides**: If the caller explicitly sets `options.idempotency`, that choice takes precedence over the default rule.
- **Token Injection**: Mutating requests that evaluate to idempotent automatically receive a unique idempotency token header (`x-goog-gcs-idempotency-token`) if not already present. This ensures the Storage service can join retries to the original request across network attempts.

---

## Testing Requirements

All idempotency hooks must be verified with unit tests in `Tests/StorageIdempotencyTests.swift`:

- Test default / unconditioned requests (verifying `idempotency == false` and token header is absent for non-idempotent operations).
- Test conditioned requests (verifying `idempotency == true` and token header is present when preconditions are met).
- Test explicit caller overrides via `RequestOptions.with { $0.idempotency = ... }`.
- Test that caller-supplied idempotency tokens are preserved and not overwritten.
