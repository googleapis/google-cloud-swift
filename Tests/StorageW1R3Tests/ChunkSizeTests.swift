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

import ArgumentParser
@testable import StorageW1R3
import Testing

@Suite struct ChunkSizeTests {
  @Test func parseChunkSizesValid() throws {
    let sizes = try StorageW1R3.parseChunkSizes("8MiB, 16MiB,32MiB")
    #expect(sizes == [8 * 1024 * 1024, 16 * 1024 * 1024, 32 * 1024 * 1024])
  }

  @Test(arguments: [
    "",
    " , ",
    "8MiB,",
    ",8MiB",
    "invalid",
  ])
  func parseChunkSizesInvalidThrows(input: String) {
    #expect(throws: Error.self) {
      _ = try StorageW1R3.parseChunkSizes(input)
    }
  }

  @Test func pickChunkSizeFixedMode() throws {
    let parsed = try StorageW1R3.parseAsRoot([
      "--bucket-name=my-bucket",
      "--chunk-size=16MiB",
    ])
    guard let benchmark = parsed as? StorageW1R3 else {
      Issue.record("cannot convert to StorageW1R3")
      return
    }
    for _ in 0..<20 {
      #expect(benchmark.pickChunkSize() == 16 * 1024 * 1024)
    }
  }

  @Test func pickChunkSizeListMode() throws {
    let candidate1 = 8 * 1024 * 1024
    let candidate2 = 32 * 1024 * 1024
    let parsed = try StorageW1R3.parseAsRoot([
      "--bucket-name=my-bucket",
      "--chunk-sizes=8MiB,32MiB",
    ])
    guard let benchmark = parsed as? StorageW1R3 else {
      Issue.record("cannot convert to StorageW1R3")
      return
    }
    var seen = Set<Int>()
    for _ in 0..<100 {
      let picked = benchmark.pickChunkSize()
      #expect(picked == candidate1 || picked == candidate2)
      seen.insert(picked)
    }
    #expect(seen.contains(candidate1))
    #expect(seen.contains(candidate2))
  }

  @Test func pickChunkSizeRangeMode() throws {
    let minSize = 8 * 1024 * 1024
    let maxSize = 32 * 1024 * 1024
    let quantum = 8 * 1024 * 1024
    let parsed = try StorageW1R3.parseAsRoot([
      "--bucket-name=my-bucket",
      "--min-chunk-size=8MiB",
      "--max-chunk-size=32MiB",
      "--chunk-size-quantum=8MiB",
    ])
    guard let benchmark = parsed as? StorageW1R3 else {
      Issue.record("cannot convert to StorageW1R3")
      return
    }
    var seen = Set<Int>()
    for _ in 0..<100 {
      let picked = benchmark.pickChunkSize()
      #expect(picked >= minSize)
      #expect(picked <= maxSize)
      #expect(picked % quantum == 0)
      seen.insert(picked)
    }
    #expect(seen.count > 1)
  }

  @Test func pickChunkSizeSingleStepRange() throws {
    let size = 16 * 1024 * 1024
    let parsed = try StorageW1R3.parseAsRoot([
      "--bucket-name=my-bucket",
      "--min-chunk-size=16MiB",
      "--max-chunk-size=16MiB",
      "--chunk-size-quantum=8MiB",
    ])
    guard let benchmark = parsed as? StorageW1R3 else {
      Issue.record("cannot convert to StorageW1R3")
      return
    }
    for _ in 0..<10 {
      #expect(benchmark.pickChunkSize() == size)
    }
  }
}
