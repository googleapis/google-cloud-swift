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
import StorageW1R3
import Testing

@Suite struct ValidationTests {
  @Test func validConfigurationPasses() throws {
    let benchmark = StorageW1R3(
      bucketName: "my-bucket",
      minObjectSize: 1024,
      maxObjectSize: 2048,
      taskCount: 2,
      iterations: 5,
      minDeleteBatch: 10,
      maxDeleteBatch: 20,
      readCount: 3,
      clientCount: 1,
      controlClientCount: 1
    )
    try benchmark.validate()
  }

  @Test func invalidObjectSizeRangeThrows() {
    let benchmark = StorageW1R3(
      bucketName: "my-bucket",
      minObjectSize: 4096,
      maxObjectSize: 1024
    )
    #expect(throws: ValidationError.self) {
      try benchmark.validate()
    }
  }

  @Test func invalidDeleteBatchRangeThrows() {
    let benchmark = StorageW1R3(
      bucketName: "my-bucket",
      minDeleteBatch: 50,
      maxDeleteBatch: 20
    )
    #expect(throws: ValidationError.self) {
      try benchmark.validate()
    }
  }

  @Test func invalidTaskCountThrows() {
    let benchmark = StorageW1R3(
      bucketName: "my-bucket",
      taskCount: 0
    )
    #expect(throws: ValidationError.self) {
      try benchmark.validate()
    }
  }

  @Test func invalidIterationsThrows() {
    let benchmark = StorageW1R3(
      bucketName: "my-bucket",
      iterations: 0
    )
    #expect(throws: ValidationError.self) {
      try benchmark.validate()
    }
  }

  @Test func invalidReadCountThrows() {
    let benchmark = StorageW1R3(
      bucketName: "my-bucket",
      readCount: -1
    )
    #expect(throws: ValidationError.self) {
      try benchmark.validate()
    }
  }

  @Test func invalidClientCountThrows() {
    let benchmark = StorageW1R3(
      bucketName: "my-bucket",
      clientCount: 0
    )
    #expect(throws: ValidationError.self) {
      try benchmark.validate()
    }
  }

  @Test func invalidControlClientCountThrows() {
    let benchmark = StorageW1R3(
      bucketName: "my-bucket",
      controlClientCount: 0
    )
    #expect(throws: ValidationError.self) {
      try benchmark.validate()
    }
  }
}
