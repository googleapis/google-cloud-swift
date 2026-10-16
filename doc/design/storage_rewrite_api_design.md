# Design Document: GCS Swift Client Library Rewrite Object Helpers

This document outlines the API design and rationale for the multi-step object rewrite helpers (`rewriteObjectUntilDone` and `rewriteObjectProgress`) in the Google Cloud Storage (`GoogleCloudStorage`) Swift client library.

## Goal

Provide an ergonomic, resilient, and Swift-idiomatic API for driving multi-step object rewrites (`google.storage.v2.Storage.RewriteObject`) to completion while clearly distinguishing active rewrite loops from background long-running operations (LROs).

---

## 1. Background: How `RewriteObject` Works in Cloud Storage

In Google Cloud Storage, rewriting an object (`RewriteObject`) copies a source object to a destination object, optionally transforming its location, storage class, encryption key (CMEK/CSEK), or metadata.

- **Single-step completion:** When the source and destination share the same location, storage class, and encryption type, GCS typically completes the rewrite in a single RPC call (`done == true`) and returns the newly created `Object` in `RewriteResponse.resource`.
- **Multi-step loop:** When rewriting large objects across locations, storage classes, or encryption keys, a single `RewriteObject` call may only rewrite a portion of the object before returning (`done == false`) along with a `rewriteToken` and progress metrics (`totalBytesRewritten` and `objectSize`).
- **Active client-driven execution:** Unlike `google.longrunning.Operation` (LRO) resources, **object rewrites do not make progress in the background on the server**. Each `rewriteObject` RPC actively rewrites the next chunk of data. If the client stops sending requests (or cancels the task), the rewrite halts at the last completed chunk until resumed with the most recent `rewriteToken` (which remains valid for up to 1 week).

---

## 2. Client Surface & Async Sequence Interface

As established in [Google Cloud Storage Swift Client Surface Area Design](storage.md), `rewriteObject` is exposed on `StorageControlProtocol` / `StorageControlClient`. To eliminate boilerplate while supporting both simple "await final result" workflows and fine-grained progress/checkpointing workflows, we provide two helper methods as protocol extensions on `StorageControlProtocol`.

### Why `StorageControlProtocol` / `StorageControlClient` (and not `StorageProtocol` / `StorageClient`)

Although the `RewriteObject` RPC is defined in the `google.storage.v2.Storage` protobuf service, `GoogleCloudStorage` intentionally splits client responsibilities by transport and operation shape (matching `google-cloud-rust`):

- **`StorageProtocol` / `StorageClient` (Handwritten Data-Plane Veneer):** Exclusively handles streaming object payload transfers (`readObject` and `writeObject`) over JSON/REST using the resumable upload and ranged download protocols. No object payload bytes flow between the client and GCS during a `RewriteObject` operation—all data movement occurs server-side within Cloud Storage.
- **`StorageControlProtocol` / `StorageControlClient` (Unified Control & Unary gRPC Client):** Consolidates `google.storage.control.v2.StorageControl`, `google.iam.v1.IAMPolicy`, and all unary bucket and object metadata/lifecycle RPCs from `google.storage.v2.Storage` (`deleteObject`, `getObject`, `listObjects`, `updateObject`, `composeObject`, `rewriteObject`, and `moveObject`) over gRPC.
- Because the underlying `rewriteObject(request:options:)` method is generated on `StorageControlProtocol` and `StorageControlClient`, the multi-step helpers `rewriteObjectUntilDone` and `rewriteObjectProgress` belong directly alongside it on `StorageControlProtocol`.

### Decision

1. **`rewriteObjectUntilDone(request:options:onProgress:)`** — Drives the rewrite loop to completion and returns the final destination `Object`, optionally invoking an async progress closure after each step:
   ```swift
   extension StorageControlProtocol {
     public func rewriteObjectUntilDone(
       request: RewriteObjectRequest,
       options: GoogleGax.RequestOptions = .init(),
       onProgress: (@Sendable (RewriteResponse) async throws -> Void)? = nil
     ) async throws -> Object
   }
   ```

2. **`rewriteObjectProgress(request:options:)`** — Returns a `Sendable` `AsyncSequence` that lazily executes one `rewriteObject` RPC per iteration and yields each `RewriteResponse` (including intermediate responses and the final response where `done == true`):
   ```swift
   extension StorageControlProtocol {
     public func rewriteObjectProgress(
       request: RewriteObjectRequest,
       options: GoogleGax.RequestOptions = .init()
     ) -> some AsyncSequence<RewriteResponse, any Swift.Error> & Sendable
   }
   ```

### Example Usage

#### Simple completion (`rewriteObjectUntilDone`):

```swift
let request = RewriteObjectRequest().with {
  $0.sourceBucket = "projects/_/buckets/source-bucket"
  $0.sourceObject = "large-file.bin"
  $0.destinationBucket = "projects/_/buckets/dest-bucket"
  $0.destinationName = "large-file-copy.bin"
  $0.ifGenerationMatch = 0
}

let destinationObject = try await controlClient.rewriteObjectUntilDone(
  request: request
) { progress in
  print("Rewrote \(progress.totalBytesRewritten) / \(progress.objectSize) bytes")
}
```

#### Step-by-step iteration and checkpointing (`rewriteObjectProgress`):

```swift
for try await response in controlClient.rewriteObjectProgress(request: request) {
  if !response.done {
    await saveCheckpoint(token: response.rewriteToken)
  }
}
```

---

## 3. Naming Rationale: `rewriteObjectUntilDone` vs. `rewriteObjectPollingUntilDone`

Generated LRO helper methods in `google-cloud-swift` use the `*PollingUntilDone` naming convention (for example, `renameFolderPollingUntilDone` on `StorageControlProtocol`). We evaluated naming the rewrite helper `rewriteObjectPollingUntilDone` versus `rewriteObjectUntilDone`.

### Decision: Use `rewriteObjectUntilDone`

We deliberately omit `Polling` from the method name while keeping the `UntilDone` suffix:

1. **Active work vs. passive status polling:**
   - Calling `getOperation` in a `*PollingUntilDone` loop passively checks the status of work executing asynchronously on the server.
   - Calling `rewriteObject` in `rewriteObjectUntilDone` actively performs the next unit of work. If the caller cancels the task or breaks out of the loop, the rewrite stops immediately rather than continuing in the background.
2. **No polling delay between steps:**
   - LRO polling sleeps between `getOperation` calls according to `ClientOptions.pollingBackoffPolicy`.
   - `rewriteObjectUntilDone` issues `rewriteObject` calls back-to-back without artificial backoff delays so the rewrite finishes as quickly as possible.
3. **Different retry and error policies:**
   - `*PollingUntilDone` methods are governed by `ClientOptions.pollingErrorPolicy` and `ClientOptions.pollingBackoffPolicy`.
   - If `rewriteObject` were named `rewriteObjectPollingUntilDone`, users configuring `clientOptions.pollingErrorPolicy` or `clientOptions.pollingBackoffPolicy` on `StorageControlClient` would reasonably expect those policies to govern `rewriteObjectPollingUntilDone`, when in fact each step uses the standard RPC `retryPolicy` and `backoffPolicy`.
4. **Discoverability:**
   - Retaining the `UntilDone` suffix preserves autocomplete discoverability alongside `*PollingUntilDone` methods while signaling that it is not an LRO polling loop.

---

## 4. Retry, Resumption, and Idempotency Strategy

When rewriting a large object across multiple RPC steps, individual `rewriteObject` calls may encounter transient network or service errors (`503 Unavailable`, `429 Too Many Requests`, `500 Internal Server Error`, `DEADLINE_EXCEEDED`, or I/O errors).

### Decision: Rely on Per-Step `RetryPolicy` in `Clients.StorageRetry`

Each call to `self.rewriteObject(request:options:)` on `StorageControlClient` is intercepted by `Clients.StorageRetry`, which wraps each individual RPC call in a `GoogleGax._RetryLoop` using `options.retryPolicy ?? clientOptions.retryPolicy` (defaulting to `StorageBaseRetryPolicy.defaultPolicy`: 60-second time limit and 10-attempt limit) and `options.backoffPolicy ?? clientOptions.backoffPolicy`.

1. **Automatic step retry and continuation:**
   - When a transient failure occurs during step $k$, `Clients.StorageRetry` retries that exact `RewriteObjectRequest` (carrying the `rewriteToken` from step $k - 1$).
   - Once the retry succeeds, `RewriteObjectSequence` captures the new `rewriteToken` from step $k$ and advances to step $k + 1$.
2. **Per-step retry budget reset:**
   - Because each `rewriteObject` RPC creates a fresh `_RetryLoop`, the retry attempt count and 60-second retry window apply **per step** rather than across the entire multi-step rewrite. A large cross-region rewrite requiring dozens of steps will not time out simply because the cumulative transfer takes several minutes.
3. **Consistent `x-goog-gcs-idempotency-token` per step:**
   - `RewriteObjectRequest.resolveIdempotency(options:)` stamps a UUID `x-goog-gcs-idempotency-token` header for each step before entering `_RetryLoop`, ensuring all retry attempts of the same step share the same idempotency token while each new step gets a fresh token.
4. **Preconditions and idempotency (`ifGenerationMatch`):**
   - `StorageBaseRetryPolicy` enforces `StrictIdempotency`. `RewriteObjectRequest.resolveIdempotency(options:)` marks the request as idempotent only when `ifGenerationMatch != nil` (or when `options.idempotent = true` is explicitly set in `RequestOptions`). Source preconditions such as `ifSourceGenerationMatch` only constrain the source object being copied from and do not prevent overwriting a concurrently modified destination object.
   - Callers who want automatic transient retries during `rewriteObjectUntilDone` or `rewriteObjectProgress` should set `ifGenerationMatch` on `RewriteObjectRequest` (or set `options.idempotent = true`).
5. **Checkpointing and manual resumption on exhausted retries:**
   - Because `rewriteObjectProgress` yields each `RewriteResponse` (and `rewriteObjectUntilDone` passes each `RewriteResponse` to `onProgress`), callers always receive the latest `rewriteToken` after every successful step. If a subsequent step exhausts its retry budget and throws, the caller can resume the rewrite later by setting `request.rewriteToken` to the last yielded token.

---

## 5. Sequence & Iterator Semantics (`RewriteObjectSequence`)

`rewriteObjectProgress` returns an internal `RewriteObjectSequence` struct conforming to `AsyncSequence` and `Sendable`:

```swift
struct RewriteObjectSequence: AsyncSequence, Sendable {
  typealias Element = RewriteResponse
  ...
}
```

### Key Behavioral Guarantees

1. **Independent iterators:** `RewriteObjectSequence` is an immutable, `Sendable` value type. Each call to `makeAsyncIterator()` (or each `for try await` loop) creates an independent `Iterator` with its own copy of `currentRequest` and `isDone` state.
2. **Terminal state on completion or error:**
   - When a step returns `response.done == true`, the iterator yields that final `RewriteResponse` and marks `isDone = true`; subsequent calls to `next()` return `nil`.
   - In accordance with `AsyncIteratorProtocol` requirements, `isDone` is set to `true` before awaiting `rewriteRpc(currentRequest)` and only reset to `false` after verifying `response.done == false` and `!response.rewriteToken.isEmpty`. If `rewriteRpc` throws an error (or if `RequestError.malformedResponse` is thrown), subsequent calls to `next()` immediately return `nil` without issuing another RPC.
3. **Defensive validation of server responses:**
   - If the server returns `done == false` with an empty `rewriteToken`, `RewriteObjectSequence.Iterator.next()` throws `GoogleGax.RequestError.malformedResponse` rather than looping infinitely with an empty token.
   - If the server returns `done == true` with `resource == nil`, `rewriteObjectUntilDone` throws `GoogleGax.RequestError.malformedResponse`.

---

## 6. Protocol Extension Design & Mocking

Unlike `StorageProtocol.readObject(from:object:options:) -> any ReadObjectHandleProtocol` (which is a primitive protocol requirement on `StorageProtocol` because there is no underlying single-RPC download method on that protocol), `StorageControlProtocol` already defines the primitive RPC requirement:

```swift
func rewriteObject(
  request: RewriteObjectRequest, options: GoogleGax.RequestOptions
) async throws -> RewriteResponse
```

### Decision: Extension-Only Helpers Returning `some AsyncSequence`

Both `rewriteObjectUntilDone` and `rewriteObjectProgress` are implemented as protocol extension methods on `StorageControlProtocol` that delegate to `self.rewriteObject(request:options:)`, matching the pattern used by generated pagination helpers such as `listObjectsByItems`:

1. **Mocking via `rewriteObject(request:options:)`:**
   - Because both helpers call `self.rewriteObject(request:options:)`, mocking `rewriteObject` on a test double conforming to `StorageControlProtocol` automatically mocks both `rewriteObjectUntilDone` and `rewriteObjectProgress` (even when called through an existential `any StorageControlProtocol`).
   - Tests that only care about the final `Object` returned by `rewriteObjectUntilDone` can return a single `RewriteResponse` with `done = true` and `resource = expectedObject`.
   - Tests that verify multi-step progress or token checkpointing can return `done = false` with intermediate `rewriteToken` values before returning `done = true`.
2. **Opaque return type (`some AsyncSequence`) over existential or custom protocol:**
   - Because `StorageControlProtocol` is generated by `librarian` (`Sources/GoogleCloudStorage/generated/StorageControl/StorageControlProtocol.swift`) and these helpers live in a handwritten extension (`StorageControlProtocol+Rewrite.swift`), Swift dispatches extension-only methods statically and then dynamically dispatches `self.rewriteObject(request:options:)` via the protocol witness table.
   - Returning an existential `any AsyncSequence<RewriteResponse, any Swift.Error> & Sendable` or a custom protocol from an extension-only method would not enable overriding `rewriteObjectProgress` on `any StorageControlProtocol` (which would require adding the helpers as protocol requirements in the generated `StorageControlProtocol` declaration), while incurring unnecessary existential boxing overhead.

---

## 7. Alternatives Considered

### Option A: Naming the Method `rewriteObjectPollingUntilDone`
- *Description:* Match the exact `*PollingUntilDone` suffix used by generated `google.longrunning.Operation` methods.
- *Why Rejected:* Misleads callers into believing the rewrite runs asynchronously in the background on the server and is governed by `ClientOptions.pollingErrorPolicy` and `ClientOptions.pollingBackoffPolicy`. Using `rewriteObjectUntilDone` with comprehensive DocC documentation makes the active, back-to-back RPC behavior explicit.

### Option B: Wrapping the Helper in an Operation-Level `_ResumeLoop` / `ResumePolicy` (or `PollingErrorPolicy`)
- *Description:* Add an outer `_ResumeLoop` (similar to `StorageClient.readObject` and `writeObject`) or `PollingErrorPolicy` loop around `self.rewriteObject(request:options:)`.
- *Why Rejected:*
  - **Nested retry amplification:** `StorageControlClient.rewriteObject` already executes `Clients.StorageRetry` (`_RetryLoop`). Wrapping `self.rewriteObject` in an outer retry/resume loop would multiply retries (e.g., 10 RPC attempts × 3 resumes = 30 attempts) unless inner retries were disabled.
  - **Loss of per-step idempotency token reuse:** Disabling inner retries and retrying from an outer loop would generate a new `x-goog-gcs-idempotency-token` on each retry unless idempotency token management were duplicated in the helper.
  - **API surface consistency:** `ResumePolicy` is a data-plane (`StorageClient`) concept, whereas `StorageControlClient` uses `RequestOptions.retryPolicy` and `backoffPolicy` for control-plane RPCs.

### Option C: Returning a Public Concrete `RewriteObjectSequence` with `Iterator.rewriteToken`
- *Description:* Expose `RewriteObjectSequence` and `RewriteObjectSequence.Iterator` as `public` types with a `public private(set) var rewriteToken: String` property on the iterator (similar to `PaginatedResponseSequence._ItemIterator.nextPageToken`), instead of returning `some AsyncSequence<RewriteResponse, any Swift.Error> & Sendable`.
- *Trade-offs:*
  - *Pros:* Allows callers who manually drive `var iterator = sequence.makeAsyncIterator()` to read `iterator.rewriteToken` directly after a thrown error.
  - *Cons:* Expands the public type surface when every `RewriteResponse` yielded by `for try await response in client.rewriteObjectProgress(...)` (or passed to `onProgress`) already contains `response.rewriteToken` directly on the element.
- *Decision:* Return `some AsyncSequence<RewriteResponse, any Swift.Error> & Sendable` to keep the public API surface minimal, since `RewriteResponse.rewriteToken` is already part of every yielded element.

### Option D: Returning a Protocol or `any AsyncSequence` and Adding Protocol Requirements to `StorageControlProtocol`
- *Description:* Declare `rewriteObjectUntilDone` and `rewriteObjectProgress` (returning `any AsyncSequence<RewriteResponse, any Swift.Error> & Sendable` or a dedicated protocol) inside the `StorageControlProtocol` protocol definition so mocks can override the helper methods directly without implementing `rewriteObject(request:options:)`.
- *Why Rejected:*
  - Requires modifying the `librarian` code generator to inject storage-specific helper requirements into the generated `StorageControlProtocol` definition.
  - Inconsistent with generated `*ByItems` pagination helpers, which are also extension-only methods returning `some AsyncSequence` that delegate to the underlying single-page RPC requirement.
  - Mocking `rewriteObject(request:options:)` is already trivial for both single-step (`done = true`) and multi-step (`done = false` -> `done = true`) test cases and additionally exercises the real loop/validation logic in tests.
