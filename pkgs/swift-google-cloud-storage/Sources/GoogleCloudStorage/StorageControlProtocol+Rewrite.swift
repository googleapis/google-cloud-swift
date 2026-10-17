// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

public import GoogleGax

extension StorageControlProtocol {
  /// Rewrites a source object to a destination object, automatically repeating `rewriteObject`
  /// calls until the rewrite completes.
  ///
  /// Unlike `*PollingUntilDone` methods for long-running operations (`google.longrunning.Operation`),
  /// object rewrites do **not** make progress in the background on the server. Instead, each
  /// ``rewriteObject(request:options:)`` call actively rewrites a portion of the object and returns
  /// a ``RewriteResponse/rewriteToken`` when more work remains (``RewriteResponse/done`` is `false`).
  /// If the caller stops making requests (or cancels the task), the rewrite halts until resumed with
  /// the latest `rewriteToken`.
  ///
  /// Because each step is an active RPC rather than a passive status poll:
  /// - Calls are issued back-to-back without polling backoff delays.
  /// - Each individual `rewriteObject` call uses the standard request `retryPolicy` and
  ///   `backoffPolicy` (not `pollingErrorPolicy` or `pollingBackoffPolicy`). Under the default
  ///   ``StorageBaseRetryPolicy``, transient errors are retried automatically when the request is
  ///   idempotent (`request.ifGenerationMatch != nil` or `options.idempotent = true`).
  ///
  /// ### Example
  ///
  /// ```swift
  /// let request = RewriteObjectRequest().with {
  ///   $0.sourceBucket = "projects/_/buckets/source-bucket"
  ///   $0.sourceObject = "large-file.bin"
  ///   $0.destinationBucket = "projects/_/buckets/dest-bucket"
  ///   $0.destinationName = "large-file-copy.bin"
  ///   $0.ifGenerationMatch = 0
  /// }
  ///
  /// let destinationObject = try await controlClient.rewriteObjectUntilDone(
  ///   request: request
  /// ) { progress in
  ///   print("Rewrote \(progress.totalBytesRewritten) / \(progress.objectSize) bytes")
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - request: The initial ``RewriteObjectRequest``.
  ///   - options: Request options applied to each `rewriteObject` call.
  ///   - onProgress: An optional closure invoked after each `rewriteObject` call (including the final call).
  /// - Returns: The destination ``Object`` metadata once the rewrite finishes.
  /// - Throws: `RequestError.malformedResponse` if the rewrite finishes (`done == true`) without a `resource`,
  ///   or if an intermediate response (`done == false`) returns an empty `rewriteToken`.
  public func rewriteObjectUntilDone(
    request: RewriteObjectRequest,
    options: GoogleGax.RequestOptions = .init(),
    onProgress: (@Sendable (RewriteResponse) async throws -> Void)? = nil
  ) async throws -> Object {
    for try await response in self.rewriteObjectProgress(request: request, options: options) {
      try await onProgress?(response)
      if response.done {
        guard let resource = response.resource else {
          throw GoogleGax.RequestError.malformedResponse(
            "RewriteObject completed (done == true), but resource was missing.")
        }
        return resource
      }
    }
    throw GoogleGax.RequestError.malformedResponse(
      "RewriteObject sequence terminated before completion.")
  }

  /// Returns an asynchronous sequence that drives an object rewrite step by step,
  /// yielding each ``RewriteResponse`` until the rewrite completes (``RewriteResponse/done`` is `true`).
  ///
  /// Unlike long-running operations (`*PollingUntilDone`), object rewrites do **not** progress
  /// in the background; each iteration of the sequence actively invokes ``rewriteObject(request:options:)``
  /// with the ``RewriteResponse/rewriteToken`` from the previous response. Breaking out of the loop
  /// early pauses the rewrite at the last yielded `rewriteToken`, which can be passed on a new
  /// ``RewriteObjectRequest/rewriteToken`` to resume the operation later.
  ///
  /// Each step uses the standard request `retryPolicy` and `backoffPolicy`. Under the default
  /// ``StorageBaseRetryPolicy``, transient errors are retried automatically when the request is
  /// idempotent (`request.ifGenerationMatch != nil` or `options.idempotent = true`). Iterating the
  /// sequence throws `RequestError.malformedResponse` if an intermediate response (`done == false`)
  /// returns an empty `rewriteToken`.
  ///
  /// ### Example
  ///
  /// ```swift
  /// for try await response in controlClient.rewriteObjectProgress(request: request) {
  ///   if !response.done {
  ///     await saveCheckpoint(token: response.rewriteToken)
  ///   }
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - request: The initial ``RewriteObjectRequest``.
  ///   - options: Request options applied to each `rewriteObject` call.
  /// - Returns: An `AsyncSequence` of ``RewriteResponse`` values.
  public func rewriteObjectProgress(
    request: RewriteObjectRequest,
    options: GoogleGax.RequestOptions = .init()
  ) -> some AsyncSequence<RewriteResponse, any Swift.Error> & Sendable {
    let rewriteRpc = { @Sendable (req: RewriteObjectRequest) async throws -> RewriteResponse in
      try await self.rewriteObject(request: req, options: options)
    }
    return RewriteObjectSequence(request: request, rewriteRpc: rewriteRpc)
  }
}

struct RewriteObjectSequence: AsyncSequence, Sendable {
  typealias Element = RewriteResponse

  private let request: RewriteObjectRequest
  private let rewriteRpc: @Sendable (RewriteObjectRequest) async throws -> RewriteResponse

  init(
    request: RewriteObjectRequest,
    rewriteRpc: @escaping @Sendable (RewriteObjectRequest) async throws -> RewriteResponse
  ) {
    self.request = request
    self.rewriteRpc = rewriteRpc
  }

  func makeAsyncIterator() -> Iterator {
    Iterator(request: request, rewriteRpc: rewriteRpc)
  }

  struct Iterator: AsyncIteratorProtocol {
    private var currentRequest: RewriteObjectRequest
    private let rewriteRpc: @Sendable (RewriteObjectRequest) async throws -> RewriteResponse
    private var isDone = false

    init(
      request: RewriteObjectRequest,
      rewriteRpc: @escaping @Sendable (RewriteObjectRequest) async throws -> RewriteResponse
    ) {
      self.currentRequest = request
      self.rewriteRpc = rewriteRpc
    }

    mutating func next() async throws -> RewriteResponse? {
      guard !isDone else {
        return nil
      }

      isDone = true
      let response = try await rewriteRpc(currentRequest)
      if response.done {
        return response
      }

      guard !response.rewriteToken.isEmpty else {
        throw GoogleGax.RequestError.malformedResponse(
          "RewriteObject in progress (done == false), but rewriteToken was empty.")
      }

      currentRequest.rewriteToken = response.rewriteToken
      isDone = false
      return response
    }
  }
}
