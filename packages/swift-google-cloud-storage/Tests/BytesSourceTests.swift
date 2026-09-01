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
@testable import GoogleCloudStorage
import NIOCore
import Testing

@Suite struct BytesSourceTests {
  /// Tests BytesSource seeking to valid and invalid offsets.
  @Test func seek() async throws {
    let data = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    var source = BytesSource(data: data)

    #expect(source.totalSize == 10)

    // Seek to valid offset
    try await source.seek(to: 5)
    let chunk = try await source.read(maxBytes: 10)
    #expect(chunk == [5, 6, 7, 8, 9])

    // Seek to negative offset
    let negativeErr = await expectError(UploadError.self) {
      try await source.seek(to: -1)
    }
    if case .internalError(let message) = negativeErr {
      #expect(message == "Invalid seek offset: -1")
    } else {
      Issue.record("Expected .internalError, got \(String(describing: negativeErr))")
    }

    // Seek past end of data
    let pastEndErr = await expectError(UploadError.self) {
      try await source.seek(to: 20)
    }
    if case .localSourceTooSmall(let localSize, let gcsOffset) = pastEndErr {
      #expect(localSize == 10)
      #expect(gcsOffset == 20)
    } else {
      Issue.record("Expected .localSourceTooSmall, got \(String(describing: pastEndErr))")
    }
  }

  /// Tests reading chunks using Data and ByteBuffer initializers.
  @Test func readChunks() async throws {
    let data = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    var dataSrc = BytesSource(data: data)

    let chunk1 = try await dataSrc.read(maxBytes: 4)
    #expect(chunk1 == [0, 1, 2, 3])

    let chunk2 = try await dataSrc.read(maxBytes: 4)
    #expect(chunk2 == [4, 5, 6, 7])

    let chunk3 = try await dataSrc.read(maxBytes: 4)
    #expect(chunk3 == [8, 9])

    let chunk4 = try await dataSrc.read(maxBytes: 4)
    #expect(chunk4 == nil)

    // With NIOCore buffer storage
    var nioBuf = NIOCore.ByteBuffer()
    nioBuf.writeBytes([10, 11, 12, 13])
    var nioSrc = BytesSource(buffer: GoogleCloudStorage.ByteBuffer(nioBuf))
    #expect(nioSrc.totalSize == 4)

    let nioChunk1 = try await nioSrc.read(maxBytes: 2)
    #expect(nioChunk1 == [10, 11])

    let nioChunk2 = try await nioSrc.read(maxBytes: 5)
    #expect(nioChunk2 == [12, 13])

    let nioChunk3 = try await nioSrc.read(maxBytes: 1)
    #expect(nioChunk3 == nil)
  }
}
