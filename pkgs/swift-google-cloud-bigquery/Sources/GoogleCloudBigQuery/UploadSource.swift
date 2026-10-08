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

/// The bytes to upload with ``BigQueryClient/load(_:configuration:jobID:chunkSize:options:)``.
///
/// ```swift
/// let job = try await client.load(
///   .data(Data("1,alice\n2,bob\n".utf8)),
///   configuration: LoadJobConfiguration(
///     destinationTable: TableID(datasetID: "d", tableID: "people"), format: .csv))
/// try await client.waitForJob(job.id)
/// ```
public struct UploadSource: Sendable {
  enum Storage: Sendable {
    case data(Data)
    case file(URL)
    case stream(@Sendable () -> UploadReader.Next)
  }

  let storage: Storage

  /// Uploads bytes held in memory.
  public static func data(_ data: Data) -> UploadSource {
    UploadSource(storage: .data(data))
  }

  /// Uploads the contents of a local file.
  ///
  /// - Parameter url: a `file:` URL.
  public static func file(_ url: URL) -> UploadSource {
    UploadSource(storage: .file(url))
  }

  /// Uploads the bytes produced by an asynchronous sequence, in order.
  ///
  /// The sequence is iterated once per upload.
  public static func stream<S: AsyncSequence & Sendable>(_ sequence: S) -> UploadSource
  where S.Element == Data {
    UploadSource(
      storage: .stream({
        let iterator = UploadReader.IteratorBox(sequence.makeAsyncIterator())
        return { try await iterator.next() }
      }))
  }
}

/// Reads an ``UploadSource`` in chunks of a fixed size.
struct UploadReader {
  /// Returns the next piece of a stream, or `nil` at its end.
  typealias Next = () async throws -> Data?

  /// Holds a stream iterator so a closure can advance it.
  final class IteratorBox<Iterator: AsyncIteratorProtocol> where Iterator.Element == Data {
    var iterator: Iterator

    init(_ iterator: Iterator) {
      self.iterator = iterator
    }

    func next(isolation actor: isolated (any Actor)? = #isolation) async throws -> Data? {
      try await self.iterator.next(isolation: actor)
    }
  }

  private enum Input {
    case data(Data, offset: Int)
    case file(FileHandle)
    case stream(Next)
  }

  private var input: Input
  private var buffer = Data()
  private var atEnd = false

  init(_ source: UploadSource) throws {
    switch source.storage {
    case .data(let data): self.input = .data(data, offset: 0)
    case .file(let url): self.input = .file(try FileHandle(forReadingFrom: url))
    case .stream(let make): self.input = .stream(make())
    }
  }

  /// Returns the next chunk of `size` bytes, or fewer if it is the last one.
  ///
  /// - Returns: the chunk, and whether no bytes follow it.
  mutating func nextChunk(size: Int) async throws -> (data: Data, isLast: Bool) {
    // Read one byte more than the chunk so the last chunk is recognized as such.
    while !self.atEnd && self.buffer.count <= size {
      if let more = try await self.read(max: size + 1 - self.buffer.count) {
        self.buffer.append(more)
      } else {
        self.atEnd = true
      }
    }
    let count = min(size, self.buffer.count)
    let chunk = Data(self.buffer.prefix(count))
    self.buffer = Data(self.buffer.dropFirst(count))
    return (chunk, self.atEnd && self.buffer.isEmpty)
  }

  /// Closes the underlying file, if any.
  func close() {
    if case .file(let handle) = self.input { try? handle.close() }
  }

  /// Reads up to `max` bytes, or returns `nil` at the end of the input.
  private mutating func read(max: Int) async throws -> Data? {
    switch self.input {
    case .data(let data, let offset):
      guard offset < data.count else { return nil }
      let end = min(data.count, offset + max)
      self.input = .data(data, offset: end)
      return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + end))
    case .file(let handle):
      guard let data = try handle.read(upToCount: max), !data.isEmpty else { return nil }
      return data
    case .stream(let next):
      while true {
        guard let data = try await next() else { return nil }
        if !data.isEmpty { return data }
      }
    }
  }
}
