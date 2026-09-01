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
import Testing

@Suite struct UploadSourceTests {
  /// Tests BytesSource seeking to valid and invalid offsets.
  @Test func bytesSourceSeek() async throws {
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

  /// Tests FileSource seeking to valid and invalid offsets.
  @Test func fileSourceSeek() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
    let fileURL = tempDirectory.appendingPathComponent("test_source_\(UUID().uuidString).txt")
    let data = Data(repeating: 65, count: 100)
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    var source = FileSource(fileURL: fileURL)
    #expect(source.totalSize == 100)

    // Seek to valid offset
    try await source.seek(to: 50)
    let chunk = try await source.read(maxBytes: 100)
    #expect(chunk?.count == 50)

    // Seek to negative offset
    let negativeErr = await expectError(UploadError.self) {
      try await source.seek(to: -5)
    }
    if case .internalError(let message) = negativeErr {
      #expect(message == "Invalid seek offset: -5")
    } else {
      Issue.record("Expected .internalError, got \(String(describing: negativeErr))")
    }

    // Seek past end of file
    let pastEndErr = await expectError(UploadError.self) {
      try await source.seek(to: 200)
    }
    if case .localSourceTooSmall(let localSize, let gcsOffset) = pastEndErr {
      #expect(localSize == 100)
      #expect(gcsOffset == 200)
    } else {
      Issue.record("Expected .localSourceTooSmall, got \(String(describing: pastEndErr))")
    }
  }
}
