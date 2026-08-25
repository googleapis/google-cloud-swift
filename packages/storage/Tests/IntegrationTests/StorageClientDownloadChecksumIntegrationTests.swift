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

import Crypto
import Foundation
@_spi(GoogleCloudInternal) import GoogleCloudGax
@testable import GoogleCloudStorage
import NIOCore
import Testing

@Suite(
  .enabled(
    if: ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil
      && ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] != nil))
struct StorageClientDownloadChecksumIntegrationTests {
  struct FixtureState: Sendable {
    let bucketName: String
    let objectName: String
    let data: Data
    let crc32cBase64: String
    let md5Base64: String
  }

  static let bucketName = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"]!

  static let sharedFixture = Task<FixtureState, any Error> {
    let objName = "test-download-checksums-\(UUID().uuidString).txt"
    let content =
      "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ - Checksum verification payload for integration tests!"
    let data = Data(content.utf8)

    let storageClient = try StorageClient()
    let uploadTask = storageClient.upload(data, to: bucketName, as: objName)
    let obj = try await uploadTask.value
    #expect(obj.bucket == bucketName)
    #expect(obj.name == objName)

    let computedCrc = _CRC32C.compute(data)
    let crcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) { Data($0).base64EncodedString() }
    let md5Base64 = Data(Insecure.MD5.hash(data: data)).base64EncodedString()

    return FixtureState(
      bucketName: bucketName,
      objectName: objName,
      data: data,
      crc32cBase64: crcBase64,
      md5Base64: md5Base64
    )
  }

  @Test func testDownloadDefaultCRC32C() async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()

    let result = storage.readObject(from: fixture.bucketName, object: fixture.objectName)
    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData == fixture.data)
  }

  @Test func testDownloadAutoMD5() async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()

    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    let result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: options)
    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData == fixture.data)
  }

  @Test func testDownloadDualAutoChecksums() async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()

    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: .auto, md5: .auto)
    }
    let result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: options)
    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData == fixture.data)
  }

  @Test func testDownloadUserProvidedChecksums() async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()

    // User-provided CRC32C
    let crcOptions = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: .value(fixture.crc32cBase64), md5: nil)
    }
    let crcResult = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: crcOptions)
    var crcData = Data()
    for try await chunk in crcResult.body {
      crcData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(crcData == fixture.data)

    // User-provided MD5
    let md5Options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .value(fixture.md5Base64))
    }
    let md5Result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: md5Options)
    var md5Data = Data()
    for try await chunk in md5Result.body {
      md5Data.append(contentsOf: chunk.readableBytesView)
    }
    #expect(md5Data == fixture.data)

    // User-provided dual CRC32C and MD5
    let dualOptions = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(
        crc32c: .value(fixture.crc32cBase64), md5: .value(fixture.md5Base64))
    }
    let dualResult = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: dualOptions)
    var dualData = Data()
    for try await chunk in dualResult.body {
      dualData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(dualData == fixture.data)
  }

  @Test func testDownloadDisabledChecksums() async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()

    let options = ReadObjectOptions().with {
      $0.checksums = .none
    }
    let result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: options)
    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData == fixture.data)
  }

  @Test(arguments: [
    (ChecksumOptions(crc32c: "AAAAAA==", md5: nil), "AAAAAA==", "crc32c"),
    (ChecksumOptions(crc32c: 0x1234_5678, md5: nil), "EjRWeA==", "crc32c"),
    (ChecksumOptions(crc32c: nil, md5: "AAAAAA=="), "AAAAAA==", "md5"),
    (ChecksumOptions(crc32c: .auto, md5: "AAAAAA=="), "AAAAAA==", "md5"),
  ])
  func testDownloadMismatchedChecksumThrows(
    checksums: ChecksumOptions,
    expectedMismatch: String,
    expectedAlgorithm: String
  ) async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()

    let options = ReadObjectOptions().with {
      $0.checksums = checksums
    }
    let result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: options)
    do {
      for try await _ in result.body {}
      Issue.record("Expected DownloadError.checksumMismatch for \(checksums)")
    } catch let error as DownloadError {
      if case .checksumMismatch(let expected, _, let algorithm) = error {
        #expect(expected == expectedMismatch)
        #expect(algorithm == expectedAlgorithm)
      } else {
        Issue.record("Expected .checksumMismatch, got \(error)")
      }
    }
  }

  @Test func testRangedDownloadChecksums() async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()

    // 1. Ranged download with default .auto skips full-object checksum verification
    let rangedAutoOptions = ReadObjectOptions().with {
      $0.range = .bounded(0...9)
    }
    let rangedAutoResult = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: rangedAutoOptions)
    var rangedAutoData = Data()
    for try await chunk in rangedAutoResult.body {
      rangedAutoData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(rangedAutoData == fixture.data.subdata(in: 0..<10))

    // 2. Ranged download with user-provided expected range checksums
    let rangeSlice = fixture.data.subdata(in: 0..<10)
    let rangeCrc = _CRC32C.compute(rangeSlice)
    let rangeCrcBase64 = withUnsafeBytes(of: rangeCrc.bigEndian) {
      Data($0).base64EncodedString()
    }
    let rangeMd5Base64 = Data(Insecure.MD5.hash(data: rangeSlice)).base64EncodedString()

    // 2a. User-provided range CRC32C
    let rangedCrcOptions = ReadObjectOptions().with {
      $0.range = .bounded(0...9)
      $0.checksums = ChecksumOptions(crc32c: .value(rangeCrcBase64), md5: nil)
    }
    let rangedCrcResult = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: rangedCrcOptions)
    var rangedCrcData = Data()
    for try await chunk in rangedCrcResult.body {
      rangedCrcData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(rangedCrcData == rangeSlice)

    // 2b. User-provided range MD5
    let rangedMd5Options = ReadObjectOptions().with {
      $0.range = .bounded(0...9)
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .value(rangeMd5Base64))
    }
    let rangedMd5Result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: rangedMd5Options)
    var rangedMd5Data = Data()
    for try await chunk in rangedMd5Result.body {
      rangedMd5Data.append(contentsOf: chunk.readableBytesView)
    }
    #expect(rangedMd5Data == rangeSlice)
  }

  @Test(arguments: [
    (ChecksumOptions(crc32c: "bad_crc_range", md5: nil), "bad_crc_range", "crc32c"),
    (ChecksumOptions(crc32c: nil, md5: "bad_md5_range"), "bad_md5_range", "md5"),
  ])
  func testRangedDownloadMismatchedChecksumThrows(
    checksums: ChecksumOptions,
    expectedMismatch: String,
    expectedAlgorithm: String
  ) async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()

    let options = ReadObjectOptions().with {
      $0.range = .bounded(0...9)
      $0.checksums = checksums
    }
    let result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: options)
    do {
      for try await _ in result.body {}
      Issue.record("Expected DownloadError.checksumMismatch on invalid range checksum")
    } catch let error as DownloadError {
      if case .checksumMismatch(let expected, _, let algorithm) = error {
        #expect(expected == expectedMismatch)
        #expect(algorithm == expectedAlgorithm)
      } else {
        Issue.record("Expected .checksumMismatch, got \(error)")
      }
    }
  }
}
