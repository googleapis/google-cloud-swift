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
@_spi(GoogleCloudInternal) import GoogleCloudGax
@testable import GoogleCloudGax
import Testing

@Suite struct CRC32CTests {
  @Test(arguments: [
    ("", UInt32(0)),
    (hello, helloCRC32C),
    (spanish, spanishCRC32C),
    (zebras, zebrasCRC32C),
    (fox, foxCRC32C),
    (gettysburg, gettysburgCRC32C),
  ])
  func compute(input: String, want: UInt32) {
    let data = Data(input.utf8)
    let got = _CRC32C.compute(data)
    #expect(want == got)

    let swGot = _CRC32C.computeSoftware(data)
    #expect(want == swGot)
  }

  @Test func update() {
    var checksum = _CRC32C()
    checksum.update(Data("Hello".utf8))
    checksum.update(Data(" ".utf8))
    checksum.update(Data("World".utf8))
    let got = checksum.finalize()
    #expect(helloCRC32C == got)

    var swChecksum = _CRC32C()
    Data("Hello".utf8).withUnsafeBytes { swChecksum.updateSoftware($0) }
    Data(" ".utf8).withUnsafeBytes { swChecksum.updateSoftware($0) }
    Data("World".utf8).withUnsafeBytes { swChecksum.updateSoftware($0) }
    let swGot = swChecksum.finalize()
    #expect(helloCRC32C == swGot)
  }

  @Test func finalizeIsNonDestructive() {
    var checksum = _CRC32C()
    checksum.update(Data("Hello".utf8))
    let first = checksum.finalize()
    let second = checksum.finalize()
    #expect(first == second)

    // Continue updating and ensure stream continues accurately
    checksum.update(Data(" ".utf8))
    checksum.update(Data("World".utf8))
    #expect(checksum.finalize() == helloCRC32C)
  }

  @Test func hardwareAccelerationDetected() {
    #if arch(x86_64) || arch(arm64)
      #expect(_CRC32C.isHardwareAccelerated)
    #endif
  }

  @Test func equivalenceAcrossLengths() {
    // Deterministic pseudo-random byte pattern
    var testData = [UInt8]()
    for i in 0..<1024 {
      testData.append(UInt8((i * 31 + 17) & 0xFF))
    }

    let lengths = [
      0, 1, 2, 3, 4, 7, 8, 9, 15, 16, 31, 32, 33, 63, 64, 65, 127, 128, 255, 256, 512, 1024,
    ]
    for len in lengths {
      let slice = Array(testData.prefix(len))
      slice.withUnsafeBytes { buffer in
        let hw = _CRC32C.compute(buffer)
        let sw = _CRC32C.computeSoftware(buffer)
        #expect(hw == sw, "Mismatch for length \(len)")
      }
    }
  }

  @Test func unalignedSlices() {
    var testData = [UInt8]()
    for i in 0..<256 {
      testData.append(UInt8(i & 0xFF))
    }

    testData.withUnsafeBytes { buffer in
      // Test slices starting at various unaligned offsets
      for offset in 1..<8 {
        for len in [1, 5, 8, 17, 33, 65, 100] {
          if offset + len <= buffer.count {
            let slice = UnsafeRawBufferPointer(
              rebasing: buffer[offset..<(offset + len)]
            )
            let hw = _CRC32C.compute(slice)
            let sw = _CRC32C.computeSoftware(slice)
            #expect(hw == sw, "Mismatch at offset \(offset), length \(len)")
          }
        }
      }
    }
  }

  @Test func chunkedEquivalence() {
    var testData = [UInt8]()
    for i in 0..<300 {
      testData.append(UInt8((i * 13 + 7) & 0xFF))
    }

    var full = _CRC32C()
    testData.withUnsafeBytes { full.update($0) }

    var chunked = _CRC32C()
    let chunks = [3, 7, 16, 1, 32, 64, 11, 8, 4, 2, 152]
    var start = 0
    for chunkLen in chunks {
      let sub = Array(testData[start..<(start + chunkLen)])
      sub.withUnsafeBytes { chunked.update($0) }
      start += chunkLen
    }

    #expect(full.finalize() == chunked.finalize())
  }

  @Test(arguments: [
    ([UInt8](repeating: 0x00, count: 32), UInt32(0x8A91_36AA)),
    ([UInt8](repeating: 0xFF, count: 32), UInt32(0x62A8_AB43)),
    (Array(0..<32).map { UInt8($0) }, UInt32(0x46DD_794E)),
    (Array(0..<32).reversed().map { UInt8($0) }, UInt32(0x113F_DB5C)),
  ])
  func rfc3720(bytes: [UInt8], want: UInt32) {
    bytes.withUnsafeBytes { buffer in
      let got = _CRC32C.compute(buffer)
      #expect(want == got)

      let swGot = _CRC32C.computeSoftware(buffer)
      #expect(want == swGot)
    }
  }

  @Test func exhaustiveOffsetAndLengthEquivalence() {
    var testData = [UInt8]()
    for i in 0..<256 {
      testData.append(UInt8((i * 31 + 17) & 0xFF))
    }

    testData.withUnsafeBytes { buffer in
      for offset in 0..<8 {
        for len in 0...128 {
          let slice = UnsafeRawBufferPointer(
            rebasing: buffer[offset..<(offset + len)]
          )
          let hw = _CRC32C.compute(slice)
          let sw = _CRC32C.computeSoftware(slice)
          #expect(hw == sw, "Mismatch at offset \(offset), length \(len)")
        }
      }
    }
  }

  @Test func seed() {
    let data1 = Data("Hello ".utf8)
    let data2 = Data("World".utf8)
    let fullCRC = _CRC32C.compute(Data("Hello World".utf8))

    let crc1 = _CRC32C.compute(data1)

    var checksum = _CRC32C(seed: crc1)
    checksum.update(data2)
    #expect(fullCRC == checksum.finalize())

    var swChecksum = _CRC32C(seed: crc1)
    data2.withUnsafeBytes { swChecksum.updateSoftware($0) }
    #expect(fullCRC == swChecksum.finalize())
  }

  @Test func emptyUnalignedBuffer() {
    let testData: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
    testData.withUnsafeBytes { buffer in
      for offset in 0..<8 {
        let slice = UnsafeRawBufferPointer(rebasing: buffer[offset..<offset])
        #expect(_CRC32C.compute(slice) == 0)
        #expect(_CRC32C.computeSoftware(slice) == 0)
      }
    }
  }

  @Test func unalignedChunkedEquivalence() {
    var testData = [UInt8]()
    for i in 0..<512 {
      testData.append(UInt8((i * 43 + 23) & 0xFF))
    }

    let full = _CRC32C.compute(Data(testData))

    testData.withUnsafeBytes { buffer in
      var chunked = _CRC32C()
      var swChunked = _CRC32C()
      let chunkSizes = [1, 3, 7, 15, 31, 33, 64, 5, 12, 128, 213]
      var offset = 0
      for size in chunkSizes {
        let slice = UnsafeRawBufferPointer(rebasing: buffer[offset..<(offset + size)])
        chunked.update(slice)
        swChunked.updateSoftware(slice)
        offset += size
      }
      #expect(full == chunked.finalize())
      #expect(full == swChunked.finalize())
    }
  }

  @Test func benchmarkFast() {
    runBenchmark(sizeMB: 1, iterations: 10)
  }

  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_CRC32C_BENCHMARK"] == "long"
    )
  )
  func benchmarkLong() {
    runBenchmark(sizeMB: 32, iterations: 20)
  }

  private func runBenchmark(sizeMB: Int, iterations: Int) {
    let size = sizeMB * 1024 * 1024
    let data = [UInt8](repeating: 0xAB, count: size)

    let clock = ContinuousClock()

    var swResult: UInt32 = 0
    let swDuration = clock.measure {
      data.withUnsafeBytes { buffer in
        for _ in 0..<iterations {
          swResult = _CRC32C.computeSoftware(buffer)
        }
      }
    }

    var hwResult: UInt32 = 0
    let hwDuration = clock.measure {
      data.withUnsafeBytes { buffer in
        for _ in 0..<iterations {
          hwResult = _CRC32C.compute(buffer)
        }
      }
    }

    let totalBytes = Double(size * iterations)
    let totalGB = totalBytes / Double(1024 * 1024 * 1024)

    let swSeconds =
      Double(swDuration.components.seconds) + Double(swDuration.components.attoseconds) * 1e-18
    let hwSeconds =
      Double(hwDuration.components.seconds) + Double(hwDuration.components.attoseconds) * 1e-18

    let swGBs = swSeconds > 0 ? totalGB / swSeconds : 0.0
    let hwGBs = hwSeconds > 0 ? totalGB / hwSeconds : 0.0
    let speedup = hwSeconds > 0 ? swSeconds / hwSeconds : 1.0

    print(
      """
      --- CRC32C Throughput Benchmark ---
      Buffer size: \(sizeMB) MiB, Iterations: \(iterations) (Total: \(String(format: "%.1f", totalGB * 1024)) MiB)
      Software: \(String(format: "%.4f", swSeconds))s (\(String(format: "%.2f", swGBs)) GB/s) -> result: 0x\(String(swResult, radix: 16))
      Hardware: \(String(format: "%.4f", hwSeconds))s (\(String(format: "%.2f", hwGBs)) GB/s) -> result: 0x\(String(hwResult, radix: 16))
      Speedup:  \(String(format: "%.1f", speedup))x
      -----------------------------------
      """
    )

    if _CRC32C.isHardwareAccelerated {
      #expect(hwResult == swResult)
      #expect(
        hwDuration < swDuration, "Hardware acceleration should be faster than software fallback")
    }
  }
}

// We can get these magic value using:
//   gcloud storage hash --skip-md5 file.txt
// And then manipulate the output with your favorite base64 decoder.
let helloCRC32C: UInt32 = 0x691daa2f  // 0xaa2f691d
let hello = "Hello World"

let spanishCRC32C: UInt32 = 0xc72af3d3
let spanish =
  "Benjamín pidió una bebida de kiwi y fresa. Noé, sin vergüenza, la más exquisita champaña del menú"

let zebrasCRC32C: UInt32 = 0xf5eb161d
let zebras = "how vexingly quick daft zebras jump"

let foxCRC32C: UInt32 = 0x3c18f4d6
let fox = "the quick brown fox jumps over the lazy dog"

let gettysburgCRC32C: UInt32 = 0x802a36d6
let gettysburg = """
  Four score and seven years ago our fathers brought forth on this continent a new
  nation, conceived in liberty, and dedicated to the proposition that all men are
  created equal.

  Now we are engaged in a great civil war, testing whether that nation, or any
  nation so conceived and so dedicated, can long endure. We are met on a great
  battlefield of that war. We have come to dedicate a portion of that field as a
  final resting place for those who here gave their lives that that nation might
  live. It is altogether fitting and proper that we should do this.

  But in a larger sense we cannot dedicate, we cannot consecrate, we cannot hallow
  this ground. The brave men, living and dead, who struggled here have consecrated
  it, far above our poor power to add or detract. The world will little note, nor
  long remember, what we say here, but it can never forget what they did here. It
  is for us the living, rather, to be dedicated here to the unfinished work which
  they who fought here have thus far so nobly advanced. It is rather for us to be
  here dedicated to the great task remaining before us,that from these honored
  dead we take increased devotion to that cause for which they gave the last full
  measure of devotion, that we here highly resolve that these dead shall not have
  died in vain, that this nation, under God, shall have a new birth of freedom,
  and that government of the people, by the people, for the people, shall not
  perish from the earth.

  """
