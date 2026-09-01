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

/// An upload source that reads from a local file.
public struct FileSource: SeekableUploadSource {
  public let fileURL: URL
  private var offset: Int64 = 0

  public var totalSize: Int64? {
    do {
      let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
      return values.fileSize.map { Int64($0) }
    } catch {
      return nil
    }
  }

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }
    try handle.seek(toOffset: UInt64(offset))
    guard let data = try handle.read(upToCount: maxBytes), !data.isEmpty else {
      return nil
    }
    offset += Int64(data.count)
    return ByteBuffer(data)
  }

  public mutating func seek(to offset: Int64) async throws {
    guard offset >= 0 else {
      throw UploadError.internalError("Invalid seek offset: \(offset)")
    }
    if let size = totalSize, offset > size {
      throw UploadError.localSourceTooSmall(localSize: size, gcsOffset: offset)
    }
    self.offset = offset
  }
}
