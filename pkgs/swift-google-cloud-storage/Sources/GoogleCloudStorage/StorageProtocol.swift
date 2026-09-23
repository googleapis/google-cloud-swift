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

  /// Resumes a previously interrupted file upload using a saved upload ID (Session URI).
  func resumeWriteObject(
    _ source: some SeekableWriteObjectSource,
    uploadId: String,
    options: WriteObjectOptions
  ) async throws -> Object

  /// Reads (downloads) an object from Cloud Storage as an async sequence of ByteChunk chunks.
  func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions
  ) -> ReadObjectTask
}

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

  /// Resumes a previously interrupted file upload using a saved upload ID (Session URI).
  public func resumeWriteObject(
    _ source: some SeekableWriteObjectSource,
    uploadId: String,
    options: WriteObjectOptions
  ) async throws -> Object {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Reads (downloads) an object from Cloud Storage as an async sequence of ByteChunk chunks.
  public func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions
  ) -> ReadObjectTask {
    fatalError("readObject(from:object:options:) has not been implemented")
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

  /// Resumes a previously interrupted file upload using a saved upload ID with default options.
  public func resumeWriteObject(
    _ source: some SeekableWriteObjectSource,
    uploadId: String
  ) async throws -> Object {
    try await self.resumeWriteObject(source, uploadId: uploadId, options: .default)
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

  /// Reads (downloads) an object from Cloud Storage with default options.
  public func readObject(
    from bucket: String,
    object: String
  ) -> ReadObjectTask {
    self.readObject(from: bucket, object: object, options: .init())
  }
}
