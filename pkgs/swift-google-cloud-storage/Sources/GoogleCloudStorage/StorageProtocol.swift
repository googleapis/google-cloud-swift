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

public import Foundation
import GoogleGax

/// Protocol defining the high-level object data-plane operations.
public protocol StorageProtocol: Sendable {
  /// Core write method accepting any write object source.
  func writeObject(
    _ source: some WriteObjectSource,
    to bucket: String,
    as objectName: String,
    options: WriteObjectOptions
  ) async throws -> Object

  /// Write method specialized for seekable write object sources.
  func writeObject(
    _ source: some SeekableWriteObjectSource,
    to bucket: String,
    as objectName: String,
    options: WriteObjectOptions
  ) async throws -> Object

  /// Starts an object download from Cloud Storage.
  ///
  /// Iterate over ``ReadObjectHandleProtocol/body`` on the returned ``ReadObjectHandleProtocol`` to stream the
  /// object's content as an asynchronous sequence of ``ByteChunk`` chunks, or `await`
  /// ``ReadObjectHandleProtocol/metadata`` to inspect the object's metadata.
  ///
  /// - Parameters:
  ///   - bucket: The GCS bucket name.
  ///   - object: The GCS object name.
  ///   - options: Configuration options for the read operation.
  /// - Returns: A ``ReadObjectHandleProtocol`` providing access to the object's ``ReadObjectHandleProtocol/metadata`` and streaming ``ReadObjectHandleProtocol/body``.
  func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions
  ) -> any ReadObjectHandleProtocol
}

private struct UnimplementedReadObjectHandle: ReadObjectHandleProtocol {}

extension StorageProtocol {
  /// Core write method accepting any write object source.
  public func writeObject(
    _ source: some WriteObjectSource,
    to bucket: String,
    as objectName: String,
    options: WriteObjectOptions
  ) async throws -> Object {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Write method specialized for seekable write object sources.
  public func writeObject(
    _ source: some SeekableWriteObjectSource,
    to bucket: String,
    as objectName: String,
    options: WriteObjectOptions
  ) async throws -> Object {
    let unseekableSource: any WriteObjectSource = source
    return try await self.writeObject(
      unseekableSource, to: bucket, as: objectName, options: options)
  }

  /// Starts an object download from Cloud Storage.
  public func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions
  ) -> any ReadObjectHandleProtocol {
    UnimplementedReadObjectHandle()
  }

  /// Core write method accepting any write object source with default options.
  public func writeObject(
    _ source: some WriteObjectSource,
    to bucket: String,
    as objectName: String
  ) async throws -> Object {
    try await self.writeObject(source, to: bucket, as: objectName, options: .default)
  }

  /// Write method specialized for seekable write object sources with default options.
  public func writeObject(
    _ source: some SeekableWriteObjectSource,
    to bucket: String,
    as objectName: String
  ) async throws -> Object {
    try await self.writeObject(source, to: bucket, as: objectName, options: .default)
  }

  /// Convenience write method for a local file URL.
  public func writeObject(
    _ fileURL: URL,
    to bucket: String,
    as objectName: String,
    options: WriteObjectOptions = .default
  ) async throws -> Object {
    try await self.writeObject(
      FileSource(fileURL: fileURL), to: bucket, as: objectName, options: options)
  }

  /// Convenience write method for in-memory Data.
  public func writeObject(
    _ data: Data,
    to bucket: String,
    as objectName: String,
    options: WriteObjectOptions = .default
  ) async throws -> Object {
    try await self.writeObject(
      BytesSource(data: data), to: bucket, as: objectName, options: options)
  }

  /// Starts an object download from Cloud Storage with default options.
  ///
  /// Iterate over ``ReadObjectHandleProtocol/body`` on the returned ``ReadObjectHandleProtocol`` to stream the
  /// object's content as an asynchronous sequence of ``ByteChunk`` chunks, or `await`
  /// ``ReadObjectHandleProtocol/metadata`` to inspect the object's metadata.
  ///
  /// ```swift
  /// let download = client.readObject(from: "my-bucket", object: "file.txt")
  /// for try await chunk in download.body {
  ///   // Process ByteChunk chunk
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - bucket: The GCS bucket name.
  ///   - object: The GCS object name.
  /// - Returns: A ``ReadObjectHandleProtocol`` providing access to the object's ``ReadObjectHandleProtocol/metadata`` and streaming ``ReadObjectHandleProtocol/body``.
  public func readObject(
    from bucket: String,
    object: String
  ) -> any ReadObjectHandleProtocol {
    self.readObject(from: bucket, object: object, options: .init())
  }
}
