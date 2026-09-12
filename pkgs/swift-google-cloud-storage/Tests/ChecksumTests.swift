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
// See the License for theing specific language governing permissions and
// limitations under the License.

import Crypto
import Foundation
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct ChecksumTests {
  @Test func testChecksummedSourceCRC32C() async throws {
    let data1 = Data("Hello, ".utf8)
    let data2 = Data("World!".utf8)
    let combinedData = data1 + data2

    let source = BytesSource(data: combinedData)
    var checksummedSource = ChecksummedSource(source: source, validation: .crc32c)

    // Read first chunk
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk1 != nil)
    #expect(chunk1!.data == ByteBuffer(data1))
    #expect(chunk1!.isLast == false)
    #expect(chunk1!.checksum == nil)

    // Read second chunk
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk2 != nil)
    #expect(chunk2!.data == ByteBuffer(data2))
    #expect(chunk2!.isLast == true)
    #expect(chunk2!.checksum != nil)

    // Expected checksum for "Hello, World!"
    #expect(chunk2!.checksum == "crc32c=TVUQaA==")
  }

  @Test func testChecksummedSourceMD5() async throws {
    let data1 = Data("Hello, ".utf8)
    let data2 = Data("World!".utf8)
    let combinedData = data1 + data2

    let source = BytesSource(data: combinedData)
    var checksummedSource = ChecksummedSource(source: source, validation: .md5)

    // Read first chunk
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk1 != nil)
    #expect(chunk1!.data == ByteBuffer(data1))
    #expect(chunk1!.isLast == false)
    #expect(chunk1!.checksum == nil)

    // Read second chunk
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk2 != nil)
    #expect(chunk2!.data == ByteBuffer(data2))
    #expect(chunk2!.isLast == true)
    #expect(chunk2!.checksum != nil)

    // Expected checksum for "Hello, World!"
    #expect(chunk2!.checksum == "md5=ZajifYh5KDgxtmS9i38K1A==")
  }

  @Test func testSimpleUploadChecksumMismatch() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data("Small payload".utf8)
    let source = BytesSource(data: data)

    let uploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    let errorMessage =
      "Provided CRC32C \"invalid_crc\" doesn't match calculated CRC32C \"valid_crc\""
    registry.register(
      response: .success(
        statusCode: 400, data: Data(errorMessage.utf8),
        headers: nil),
      for: uploadUrl)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, mock: registry)
    let uploadOptions = UploadOptions().with { $0.validation = .crc32c }

    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    }
    if case .http(let details) = error {
      #expect(details.httpStatusCode == 400)
      #expect(String(data: details.payload, encoding: .utf8) == errorMessage)
    } else {
      Issue.record("Expected .http RequestError, got \(String(describing: error))")
    }
  }

  @Test func testResumableUploadChecksumMismatch() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB to trigger resumable upload
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    let errorMessage = "Provided MD5 \"invalid_md5\" doesn't match calculated MD5 \"valid_md5\""

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 400, data: Data(errorMessage.utf8),
        headers: nil),
      for: chunkUrl)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, mock: registry)
    let uploadOptions = UploadOptions().with { $0.validation = .md5 }

    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    }
    if case .http(let details) = error {
      #expect(details.httpStatusCode == 400)
      #expect(String(data: details.payload, encoding: .utf8) == errorMessage)
    } else {
      Issue.record("Expected .http RequestError, got \(String(describing: error))")
    }
  }

  @Test func testChecksummedSourceMultipleAuto() async throws {
    let data1 = Data("Hello, ".utf8)
    let data2 = Data("World!".utf8)
    let combinedData = data1 + data2

    let source = BytesSource(data: combinedData)
    let checksums = ChecksumOptions(crc32c: .auto, md5: .auto)
    var checksummedSource = ChecksummedSource(source: source, options: checksums)

    _ = try await checksummedSource.readChunk(maxBytes: 7)
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 7)

    #expect(chunk2 != nil)
    #expect(chunk2!.isLast == true)
    #expect(chunk2!.checksum == "crc32c=TVUQaA==, md5=ZajifYh5KDgxtmS9i38K1A==")
  }

  @Test func testChecksummedSourceUserProvidedValues() async throws {
    let source = BytesSource(data: Data("Some data".utf8))
    let checksums = ChecksumOptions(crc32c: "PRE_CRC", md5: "PRE_MD5")
    var checksummedSource = ChecksummedSource(source: source, options: checksums)

    let chunk = try await checksummedSource.readChunk(maxBytes: 100)

    #expect(chunk != nil)
    #expect(chunk!.isLast == true)
    #expect(chunk!.checksum == "crc32c=PRE_CRC, md5=PRE_MD5")
  }

  @Test func testChecksummedSourceUserProvidedUInt32() async throws {
    let source = BytesSource(data: Data("Hello, World!".utf8))
    // 0x4D551068 (big-endian [0x4D, 0x55, 0x10, 0x68]) encodes to "TVUQaA=="
    let checksumsLiteral = ChecksumOptions(crc32c: 0x4D551068)
    #expect(checksumsLiteral.crc32c == .value("TVUQaA=="))

    var checksummedSource = ChecksummedSource(source: source, options: checksumsLiteral)
    let chunk = try await checksummedSource.readChunk(maxBytes: 100)

    #expect(chunk != nil)
    #expect(chunk!.isLast == true)
    #expect(chunk!.checksum == "crc32c=TVUQaA==")
  }

  @Test func testChecksummedSourceMixedAutoAndUserProvided() async throws {
    let data = Data("Hello, World!".utf8)
    let source = BytesSource(data: data)
    let checksums = ChecksumOptions(crc32c: .auto, md5: "CUSTOM_MD5")
    var checksummedSource = ChecksummedSource(source: source, options: checksums)

    let chunk = try await checksummedSource.readChunk(maxBytes: 100)

    #expect(chunk != nil)
    #expect(chunk!.isLast == true)
    #expect(chunk!.checksum == "crc32c=TVUQaA==, md5=CUSTOM_MD5")
  }

  /// Tests that a non-seekable UploadSource can be wrapped in ChecksummedSource and streamed cleanly.
  @Test func testChecksummedSourceNonSeekableSourceStreaming() async throws {
    struct NonSeekableSource: UploadSource {
      let data: Data
      private var readCompleted = false
      init(data: Data) { self.data = data }
      var totalSize: UInt64? { UInt64(data.count) }
      mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
        if readCompleted { return nil }
        readCompleted = true
        return ByteBuffer(data)
      }
    }

    let data = Data("streaming non-seekable data".utf8)
    let source = NonSeekableSource(data: data)
    var checksummedSource = ChecksummedSource(source: source, options: .default)

    let chunk = try await checksummedSource.readChunk(maxBytes: 100)
    #expect(chunk != nil)
    #expect(chunk?.data == ByteBuffer(data))
    #expect(chunk?.isLast == true)
    #expect(chunk?.checksum != nil)
  }

  /// Tests seeking backwards does not re-hash previously hashed bytes or corrupt the final checksum.
  @Test func testChecksummedSourceSeekBackwardsDoesNotDuplicateHashes() async throws {
    let data = Data("Hello, World!".utf8)  // CRC32C: TVUQaA==
    let source = BytesSource(data: data)
    var checksummedSource = ChecksummedSource(source: source, validation: .crc32c)

    // 1. Seek forward to byte 7 ("Hello, ") -> bytesHashed becomes 7
    try await checksummedSource.seek(to: 7)

    // 2. Seek backward to byte 0 -> should NOT reset bytesHashed (remains 7)
    try await checksummedSource.seek(to: 0)

    // 3. Read entire file from byte 0 to EOF
    var allData = Data()
    var finalChecksum: String? = nil
    while let chunk = try await checksummedSource.readChunk(maxBytes: 5) {
      allData.append(contentsOf: chunk.data)
      if chunk.isLast {
        finalChecksum = chunk.checksum
      }
    }

    #expect(allData == data)
    #expect(finalChecksum == "crc32c=TVUQaA==")
  }

  /// Tests seeking forward incrementally from an intermediate offset.
  @Test func testChecksummedSourceSeekForwardFromIntermediateOffset() async throws {
    let data = Data("Hello, World!".utf8)  // CRC32C: TVUQaA==
    let source = BytesSource(data: data)
    var checksummedSource = ChecksummedSource(source: source, validation: .crc32c)

    // 1. Seek to byte 3 -> hashes 0..<3
    try await checksummedSource.seek(to: 3)

    // 2. Seek forward to byte 7 ("Hello, ") -> hashes 3..<7 without re-hashing 0..<3
    try await checksummedSource.seek(to: 7)

    // 3. Read remaining chunks 7..<13 to EOF
    var remainingData = Data()
    var finalChecksum: String? = nil
    while let chunk = try await checksummedSource.readChunk(maxBytes: 5) {
      remainingData.append(contentsOf: chunk.data)
      if chunk.isLast {
        finalChecksum = chunk.checksum
      }
    }

    #expect(remainingData == Data("World!".utf8))
    #expect(finalChecksum == "crc32c=TVUQaA==")
  }

  @Test func testCRC32CCalculator() {
    var calculator = CRC32CCalculator()
    #expect(calculator.algorithmName == "crc32c")

    let data1 = Data("Hello, ".utf8)
    let data2 = Data("World!".utf8)
    calculator.update(data1)
    calculator.update(data2)
    #expect(calculator.finalize() == "TVUQaA==")
  }

  @Test func testCRC32CCalculatorSeeded() {
    let part1 = Data("Hello, ".utf8)
    let part2 = Data("World!".utf8)
    let seed = _CRC32C.compute(part1)

    var calc = CRC32CCalculator(seed: seed)
    calc.update(part2)
    #expect(calc.finalize() == "TVUQaA==")
  }

  @Test func testMD5Calculator() {
    var calculator = MD5Calculator()
    #expect(calculator.algorithmName == "md5")

    let data1 = Data("Hello, ".utf8)
    let data2 = Data("World!".utf8)
    calculator.update(data1)
    calculator.update(data2)
    #expect(calculator.finalize() == "ZajifYh5KDgxtmS9i38K1A==")
  }

  @Test func testProvidedChecksumCalculator() {
    var rawCalc = ProvidedChecksumCalculator(algorithmName: "crc32c", value: "TVUQaA==")
    #expect(rawCalc.algorithmName == "crc32c")
    rawCalc.update(Data("ignored data".utf8))
    #expect(rawCalc.finalize() == "TVUQaA==")

    // Prefixed value gets cleaned
    let prefixedCalc = ProvidedChecksumCalculator(algorithmName: "md5", value: "md5=custom_md5==")
    #expect(prefixedCalc.algorithmName == "md5")
    #expect(prefixedCalc.finalize() == "custom_md5==")
  }

  @Test func testMakeUploadCalculators() {
    let options = ChecksumOptions(crc32c: .auto, md5: .value("user_md5=="))
    var calcs = options.makeUploadCalculators()
    #expect(calcs.count == 2)
    #expect(calcs[0] is CRC32CCalculator)
    #expect(calcs[1] is ProvidedChecksumCalculator)

    let testData = Data("Hello, World!".utf8)
    for i in calcs.indices {
      calcs[i].update(testData)
    }

    let header = calcs.map { "\($0.algorithmName)=\($0.finalize())" }.joined(separator: ", ")
    #expect(header == "crc32c=TVUQaA==, md5=user_md5==")
  }

  /// Tests that rewinding ChecksummedSource during simulated chunk retry preserves correct CRC32C checksum.
  @Test func testChecksummedSourceRewindAndReReadMatchesDirectHashCRC32C() async throws {
    let data = Data("Hello, World!".utf8)  // CRC32C: TVUQaA==
    let source = BytesSource(data: data)
    var checksummedSource = ChecksummedSource(source: source, validation: .crc32c)

    // 1. Read chunk 1: 5 bytes ("Hello")
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 5)
    #expect(chunk1?.data == ByteBuffer(Data("Hello".utf8)))
    #expect(chunk1?.isLast == false)

    // 2. Read chunk 2: 5 bytes (", Wor") -> bytesHashed becomes 10
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 5)
    #expect(chunk2?.data == ByteBuffer(Data(", Wor".utf8)))
    #expect(chunk2?.isLast == false)

    // 3. Simulate upload failure of chunk 2: rewind to offset 5
    try await checksummedSource.seek(to: 5)

    // 4. Re-read chunk 2 from offset 5: 5 bytes (", Wor") -> should be skipped by updateChecksums
    let chunk2Retry = try await checksummedSource.readChunk(maxBytes: 5)
    #expect(chunk2Retry?.data == ByteBuffer(Data(", Wor".utf8)))
    #expect(chunk2Retry?.isLast == false)

    // 5. Read final chunk 3: 3 bytes ("ld!") -> bytesHashed becomes 13
    let chunk3 = try await checksummedSource.readChunk(maxBytes: 5)
    #expect(chunk3?.data == ByteBuffer(Data("ld!".utf8)))
    #expect(chunk3?.isLast == true)
    #expect(chunk3?.checksum == "crc32c=TVUQaA==")
  }

  /// Tests that rewinding ChecksummedSource during simulated chunk retry preserves correct MD5 checksum.
  @Test func testChecksummedSourceRewindAndReReadMatchesDirectHashMD5() async throws {
    let data = Data("Hello, World!".utf8)  // MD5: ZajifYh5KDgxtmS9i38K1A==
    let source = BytesSource(data: data)
    var checksummedSource = ChecksummedSource(source: source, validation: .md5)

    // 1. Read chunk 1: 5 bytes ("Hello")
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 5)
    #expect(chunk1?.data == ByteBuffer(Data("Hello".utf8)))
    #expect(chunk1?.isLast == false)

    // 2. Read chunk 2: 5 bytes (", Wor") -> bytesHashed becomes 10
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 5)
    #expect(chunk2?.data == ByteBuffer(Data(", Wor".utf8)))
    #expect(chunk2?.isLast == false)

    // 3. Simulate upload failure of chunk 2: rewind to offset 5
    try await checksummedSource.seek(to: 5)

    // 4. Re-read chunk 2 from offset 5: 5 bytes (", Wor")
    let chunk2Retry = try await checksummedSource.readChunk(maxBytes: 5)
    #expect(chunk2Retry?.data == ByteBuffer(Data(", Wor".utf8)))
    #expect(chunk2Retry?.isLast == false)

    // 5. Read final chunk 3: 3 bytes ("ld!") -> bytesHashed becomes 13
    let chunk3 = try await checksummedSource.readChunk(maxBytes: 5)
    #expect(chunk3?.data == ByteBuffer(Data("ld!".utf8)))
    #expect(chunk3?.isLast == true)
    #expect(chunk3?.checksum == "md5=ZajifYh5KDgxtmS9i38K1A==")
  }

  /// Tests that rewinding with unaligned chunk boundaries correctly slices unhashed data.
  @Test func testChecksummedSourceRewindWithUnalignedChunkSizes() async throws {
    let data = Data((0..<100).map { UInt8($0) })
    let source = BytesSource(data: data)
    var checksummedSource = ChecksummedSource(source: source, validation: .crc32c)

    // 1. Read first 30 bytes: 0..<30 -> bytesHashed becomes 30
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 30)
    #expect(chunk1?.data.count == 30)

    // 2. Rewind to byte 15
    try await checksummedSource.seek(to: 15)

    // 3. Read 40 bytes: 15..<55 -> bytes 15..<30 skipped, bytes 30..<55 hashed -> bytesHashed becomes 55
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 40)
    #expect(chunk2?.data.count == 40)

    // 4. Read chunk 3: 40 bytes (55..<95)
    let chunk3 = try await checksummedSource.readChunk(maxBytes: 40)
    #expect(chunk3?.data.count == 40)
    #expect(chunk3?.isLast == false)

    // 5. Read final chunk 4: remaining 5 bytes (95..<100)
    let chunk4 = try await checksummedSource.readChunk(maxBytes: 40)
    #expect(chunk4?.data.count == 5)
    #expect(chunk4?.isLast == true)

    var calc = CRC32CCalculator()
    calc.update(data)
    let expectedCRC = calc.finalize()
    #expect(chunk4?.checksum == "crc32c=\(expectedCRC)")
  }

  /// Tests that seedCRC32C discards non-seedable dynamic calculators (like MD5) when rolling back bytesHashed.
  @Test func testChecksummedSourceSeedCRC32CDiscardsNonSeedableCalculators() async throws {
    let part1 = Data("Hello, ".utf8)
    let part2 = Data("World!".utf8)
    let fullData = part1 + part2
    let source = BytesSource(data: fullData)

    let checksums = ChecksumOptions(crc32c: .auto, md5: .auto)
    var checksummedSource = ChecksummedSource(source: source, options: checksums)

    // Read first chunk (7 bytes: "Hello, ") -> both CRC32C and MD5 hash 0..<7
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk1?.data == ByteBuffer(part1))

    // Server acknowledges commit at byte 7 with running CRC32C seed
    let seed = _CRC32C.compute(part1)
    checksummedSource.seedCRC32C(seed: seed, bytesHashed: 7)

    // Read second chunk (6 bytes: "World!")
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk2?.data == ByteBuffer(part2))
    #expect(chunk2?.isLast == true)

    // MD5 was discarded because it cannot be safely reseeded; only CRC32C remains
    #expect(chunk2?.checksum == "crc32c=TVUQaA==")
  }

  /// Tests that seedCRC32C discards MD5 even when no CRC32C calculator is present.
  @Test func testChecksummedSourceSeedCRC32CDiscardsMD5WhenCRC32CNotPresent() async throws {
    let part1 = Data("Hello, ".utf8)
    let part2 = Data("World!".utf8)
    let fullData = part1 + part2
    let source = BytesSource(data: fullData)

    var checksummedSource = ChecksummedSource(source: source, validation: .md5)

    // Read first chunk (7 bytes: "Hello, ") -> MD5 hashes 0..<7
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk1?.data == ByteBuffer(part1))

    // Calling seedCRC32C discards the MD5 calculator even though there is no CRC32C calculator
    checksummedSource.seedCRC32C(seed: 12345, bytesHashed: 7)

    // Read second chunk (6 bytes: "World!")
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk2?.data == ByteBuffer(part2))
    #expect(chunk2?.isLast == true)

    // All dynamic calculators were discarded, and no CRC32C was added; checksum is nil
    #expect(chunk2?.checksum == nil)
  }
}
