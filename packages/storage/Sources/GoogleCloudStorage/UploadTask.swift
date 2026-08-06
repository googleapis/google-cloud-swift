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

import Foundation

/// Represents the current state of an ongoing upload.
public struct UploadStatus: Sendable {
  /// The fraction of the upload completed (0.0 to 1.0).
  /// This is `nil` if the total size is unknown (e.g., streaming).
  public var fractionCompleted: Double? {
    guard let totalBytes = totalBytes, totalBytes > 0 else { return nil }
    return Double(bytesUploaded) / Double(totalBytes)
  }

  /// The number of bytes successfully received by GCS.
  public let bytesUploaded: Int64

  /// The total bytes to upload. Nil if the size is unknown (streaming).
  public let totalBytes: Int64?

  /// The GCS Upload ID (Session URI).
  /// This is `nil` if the library chose a "Simple Upload".
  /// It becomes populated as soon as the Resumable Session is created.
  public let uploadId: String?

  public init(
    bytesUploaded: Int64,
    totalBytes: Int64? = nil,
    uploadId: String? = nil
  ) {
    self.bytesUploaded = bytesUploaded
    self.totalBytes = totalBytes
    self.uploadId = uploadId
  }
}

/// A handle to an ongoing upload, allowing for progress monitoring, cancellation, and awaiting the final result.
public struct UploadTask: Sendable {
  private let statusStreamController: AsyncStream<UploadStatus>.Continuation
  private let statusStream: AsyncStream<UploadStatus>
  private let valueTask: Task<Object, Error>

  internal init(
    statusStream: AsyncStream<UploadStatus>,
    statusStreamController: AsyncStream<UploadStatus>.Continuation,
    valueTask: Task<Object, Error>
  ) {
    self.statusStream = statusStream
    self.statusStreamController = statusStreamController
    self.valueTask = valueTask
  }

  /// Creates a new stream to observe the upload progress and status.
  /// Multiple observers can call this to get their own independent stream.
  /// The stream completes when the upload finishes or fails.
  public func makeStatusStream() -> AsyncStream<UploadStatus> {
    // Currently returns the single internal stream, which only supports one consumer.
    // Consider how to make this support multiple subscribers.
    return statusStream
  }

  /// The final result of the upload.
  /// Awaiting this will suspend until the upload is complete.
  public var value: Object {
    get async throws {
      return try await valueTask.value
    }
  }

  /// Cancels the ongoing upload (client-side).
  /// If cancelled, `value` will throw a `CancellationError`.
  /// Note: The GCS resumable session on the server will remain active until it expires (usually 7 days).
  public func cancel() {
    valueTask.cancel()
    statusStreamController.finish()
  }
}

// Internal factory to create an UploadTask
extension UploadTask {
  internal static func create(
    operation:
      @escaping @Sendable (AsyncStream<UploadStatus>.Continuation) async throws -> Object
  ) -> UploadTask {
    let (stream, continuation) = AsyncStream.makeStream(of: UploadStatus.self)
    let valueTask = Task {
      do {
        let result = try await operation(continuation)
        continuation.finish()
        return result
      } catch {
        continuation.finish()
        throw error
      }
    }
    return UploadTask(
      statusStream: stream, statusStreamController: continuation, valueTask: valueTask)
  }
}
