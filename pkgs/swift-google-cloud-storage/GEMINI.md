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

This directive instructs the generator to inject custom idempotency resolution at the beginning of each generated RPC method in `Sources/GoogleCloudStorage/generated/Storage/Storage+Retry.swift` and `Sources/GoogleCloudStorage/generated/StorageControl/StorageControl+Retry.swift`:

```swift
let options = request.resolveIdempotency(options: options)
```

Consequently, every request type handled by the generated `Storage` and `StorageControl` clients must provide an extension conforming to:

```swift
extension <RequestType> {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions
}
```

These extensions reside in `Sources/GoogleCloudStorage/StorageIdempotency.swift`.

---

## Idempotency Rules

When implementing or updating `resolveIdempotency(options:)` for a request type, follow the [Cloud Storage Retry Strategy — Idempotency Operations specification](https://docs.cloud.google.com/storage/docs/retry-strategy#idempotency-operations) and these rules:

1. **Read-Only Operations**:
   - The request is idempotent by default.
   - Use `resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)`.
   - Examples: `GetBucketRequest`, `ListBucketsRequest`, `GetObjectRequest`, `ListObjectsRequest`, `GetIamPolicyRequest`, `TestIamPermissionsRequest`, `GetFolderRequest`, `ListFoldersRequest`, `GetRapidCacheRequest`, `ListRapidCachesRequest`, `GetOperationRequest`.

2. **Metadata Modifications (Buckets, Objects, and Managed Folders)**:
   - The operation is idempotent **if and only if** there are preconditions on the metageneration (e.g., `self.ifMetagenerationMatch != nil` or `self.ifMetagenerationMatch > 0`).
   - Use `isMutating: true` for `Storage` requests and `isMutating: false` for `StorageControl` requests (which pass `requestId` in the request body).
   - Examples: `UpdateBucketRequest`, `LockBucketRetentionPolicyRequest`, `UpdateObjectRequest`, `UpdateManagedFolderRequest`.

3. **Delete Operations**:
   - `DeleteBucketRequest`: Always idempotent per the retry strategy specification (`isIdempotent: true, isMutating: true`).
   - `DeleteObjectRequest`: Idempotent when `self.generation != 0 || self.ifGenerationMatch != nil` (`isMutating: true`).
   - `DeleteFolderRequest`, `DeleteManagedFolderRequest`, `DeleteFolderRecursiveRequest`: Idempotent when `self.ifMetagenerationMatch != nil` (`isMutating: false`).

4. **Resource Creation, Transformations, and Control-Plane Mutations**:
   - `CreateBucketRequest`: Idempotent by default (`isIdempotent: true, isMutating: true`).
   - `ComposeObjectRequest` & `RewriteObjectRequest`: Idempotent if generation match precondition is present (`self.ifGenerationMatch != nil`, `isMutating: true`).
   - `MoveObjectRequest`: Idempotent only when preconditions are set on both source and destination (`self.ifGenerationMatch != nil && self.ifSourceGenerationMatch != nil`, `isMutating: true`).
   - `RestoreObjectRequest`: Idempotent if generation or metageneration match is present (`self.ifGenerationMatch != nil || self.ifMetagenerationMatch != nil`, `isMutating: true`).
   - `RenameFolderRequest`: Idempotent when `self.ifMetagenerationMatch != nil` (`isMutating: false`).
   - `StorageControl` `requestId`-backed mutations (`CreateFolderRequest`, `CreateManagedFolderRequest`, `*AnywhereCacheRequest`, `*RapidCacheRequest`, `Update*IntelligenceConfigRequest`): Idempotent when `!self.requestId.isEmpty` (`isMutating: false`).

5. **IAM Policy Modifications (`SetIamPolicyRequest`) and `etag` Preconditions**:
   - `GoogleIAMV1.SetIamPolicyRequest` is conditionally idempotent when `!(self.policy?.etag.isEmpty ?? true)` (`isMutating: true`) per the retry strategy specification.
   - For bucket and object operations, **never** use `ifEtagMatch` or `ifEtagNotMatch` to determine whether an operation is idempotent.

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
  let effectiveIdempotency = options.idempotent ?? isIdempotent
  options.idempotent = effectiveIdempotency
  if isMutating && effectiveIdempotency {
    if options.headers[idempotencyToken] == nil {
      options.headers[idempotencyToken] = UUID().uuidString
    }
  }
  return options
}
```

Key behaviors:
- **Caller Overrides**: If the caller explicitly sets `options.idempotent`, that choice takes precedence over the default rule.
- **Token Injection**: Mutating requests that evaluate to idempotent automatically receive a unique idempotency token header (`x-goog-gcs-idempotency-token`) if not already present. This ensures the Storage service can join retries to the original request across network attempts.

---

## Testing Requirements

All idempotency hooks must be verified with unit tests in `Tests/StorageIdempotencyTests.swift`:

- Test default / unconditioned requests (verifying `idempotent == false` and token header is absent for non-idempotent operations).
- Test conditioned requests (verifying `idempotent == true` and token header is present when preconditions are met).
- Test explicit caller overrides via `RequestOptions.with { $0.idempotent = ... }`.
- Test that caller-supplied idempotency tokens are preserved and not overwritten.
