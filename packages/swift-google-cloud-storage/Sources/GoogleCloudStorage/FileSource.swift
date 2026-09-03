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
import NIOCore

private final class FileHandleBox: @unchecked Sendable {
  let fileHandle: NIOFileHandle

  init(fileHandle: NIOFileHandle) {
    self.fileHandle = fileHandle
  }

  deinit {
    try? fileHandle.close()
  }

  static func open(fileURL: URL) throws -> FileHandleBox {
    let handle = try NIOFileHandle(_deprecatedPath: fileURL.path)
    return FileHandleBox(fileHandle: handle)
  }

  func read(maxBytes: Int, offset: UInt64) throws -> NIOCore.ByteBuffer? {
    guard let off = off_t(exactly: offset) else {
      throw UploadError.internalError("Offset exceeds maximum file offset: \(offset)")
    }
    var buffer = ByteBufferAllocator().buffer(capacity: maxBytes)
    let bytesRead = try buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: maxBytes) { ptr in
      guard let base = ptr.baseAddress else { return 0 }
      return try fileHandle.withUnsafeFileDescriptor { fd in
        let n = pread(fd, base, maxBytes, off)
        guard n >= 0 else {
          let code = errno
          throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return n
      }
    }
    guard bytesRead > 0 else { return nil }
    return buffer
  }
}

/// An upload source that reads from a local file.
public struct FileSource: SeekableUploadSource {
  public let fileURL: URL
  private var offset: UInt64 = 0
  private var handleBox: FileHandleBox?

  public var totalSize: UInt64? {
    do {
      let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
      return values.fileSize.flatMap { $0 >= 0 ? UInt64($0) : nil }
    } catch {
      return nil
    }
  }

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
    guard maxBytes > 0 else { return nil }
    if let size = totalSize, offset >= size {
      handleBox = nil
      return nil
    }

    let box: FileHandleBox
    if let existing = handleBox {
      box = existing
    } else {
      let newBox = try FileHandleBox.open(fileURL: fileURL)
      self.handleBox = newBox
      box = newBox
    }

    guard let nioBuffer = try box.read(maxBytes: maxBytes, offset: offset) else {
      handleBox = nil
      return nil
    }

    offset += UInt64(nioBuffer.readableBytes)
    return ByteBuffer(nioBuffer)
  }

  public mutating func seek(to offset: UInt64) async throws {
    if let size = totalSize, offset > size {
      throw UploadError.localSourceTooSmall(localSize: size, gcsOffset: offset)
    }
    self.offset = offset
  }
}
