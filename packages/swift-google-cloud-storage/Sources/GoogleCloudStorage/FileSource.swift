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

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#endif

private final class FileHandleBox: @unchecked Sendable {
  let fd: CInt

  init(fd: CInt) {
    self.fd = fd
  }

  deinit {
    #if canImport(Darwin)
      _ = Darwin.close(fd)
    #elseif canImport(Glibc)
      _ = Glibc.close(fd)
    #elseif canImport(Musl)
      _ = Musl.close(fd)
    #else
      _ = close(fd)
    #endif
  }

  static func open(fileURL: URL) throws -> FileHandleBox {
    let fd = try fileURL.withUnsafeFileSystemRepresentation { cPath in
      guard let cPath = cPath else {
        throw UploadError.internalError("Unable to resolve file path for URL: \(fileURL)")
      }
      #if canImport(Darwin)
        let fd = Darwin.open(cPath, O_RDONLY)
      #elseif canImport(Glibc)
        let fd = Glibc.open(cPath, O_RDONLY | O_CLOEXEC)
      #elseif canImport(Musl)
        let fd = Musl.open(cPath, O_RDONLY | O_CLOEXEC)
      #else
        let fd = open(cPath, O_RDONLY)
      #endif
      guard fd >= 0 else {
        let code = errno
        if code == ENOENT {
          throw CocoaError(.fileNoSuchFile)
        } else if code == EACCES {
          throw CocoaError(.fileReadNoPermission)
        } else {
          throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
      }
      return fd
    }
    return FileHandleBox(fd: fd)
  }

  var totalSize: UInt64? {
    var st = stat()
    #if canImport(Darwin)
      guard Darwin.fstat(fd, &st) == 0 else { return nil }
    #elseif canImport(Glibc)
      guard Glibc.fstat(fd, &st) == 0 else { return nil }
    #elseif canImport(Musl)
      guard Musl.fstat(fd, &st) == 0 else { return nil }
    #else
      guard fstat(fd, &st) == 0 else { return nil }
    #endif
    return st.st_size >= 0 ? UInt64(st.st_size) : nil
  }

  func pread(into base: UnsafeMutableRawPointer, maxBytes: Int, offset: UInt64) throws -> Int {
    guard let off = off_t(exactly: offset) else {
      throw UploadError.internalError("Offset exceeds maximum file offset: \(offset)")
    }
    #if canImport(Darwin)
      let n = Darwin.pread(fd, base, maxBytes, off)
    #elseif canImport(Glibc)
      let n = Glibc.pread(fd, base, maxBytes, off)
    #elseif canImport(Musl)
      let n = Musl.pread(fd, base, maxBytes, off)
    #else
      let n = pread(fd, base, maxBytes, off)
    #endif
    guard n >= 0 else {
      let code = errno
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    return n
  }
}

/// An upload source that reads from a local file.
public struct FileSource: SeekableUploadSource {
  public let fileURL: URL
  private var offset: UInt64 = 0
  private var handleBox: FileHandleBox?

  public var totalSize: UInt64? {
    if let size = handleBox?.totalSize {
      return size
    }
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

    var nioBuffer = ByteBufferAllocator().buffer(capacity: maxBytes)
    let currentOffset = offset
    let bytesRead = try nioBuffer.writeWithUnsafeMutableBytes(minimumWritableBytes: maxBytes) {
      ptr in
      guard let base = ptr.baseAddress else { return 0 }
      return try box.pread(into: base, maxBytes: maxBytes, offset: currentOffset)
    }

    guard bytesRead > 0 else {
      handleBox = nil
      return nil
    }

    offset += UInt64(bytesRead)
    return ByteBuffer(nioBuffer)
  }

  public mutating func seek(to offset: UInt64) async throws {
    if let size = totalSize, offset > size {
      throw UploadError.localSourceTooSmall(localSize: size, gcsOffset: offset)
    }
    self.offset = offset
  }
}
