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

@Suite struct ValidationTests {
  @Test func defaultsAreValid() throws {
    let parsed = try StorageW1R3.parseAsRoot(["--bucket-name=my-bucket"])
    guard let benchmark = parsed as? StorageW1R3 else {
      Issue.record("cannot convert to StorageW1R3")
      return
    }
    try benchmark.validate()
    #expect(benchmark.bucketName == "my-bucket")
  }

  @Test func validConfigurationPasses() throws {
    let parsed = try StorageW1R3.parseAsRoot([
      "--bucket-name=my-bucket",
      "--min-object-size=1KiB",
      "--max-object-size=2KiB",
      "--task-count=2",
      "--iterations=5",
      "--min-delete-batch=10",
      "--max-delete-batch=20",
      "--read-count=2",
      "--client-count=7",
      "--control-client-count=17",
    ])
    guard let benchmark = parsed as? StorageW1R3 else {
      Issue.record("cannot convert to StorageW1R3")
      return
    }
    try benchmark.validate()
    #expect(benchmark.bucketName == "my-bucket")
  }

  @Test(arguments:[
    ["--min-object-size=4KiB", "--max-object-size=1KiB"],
    ["--min-delete-batch=50", "--max-delete-batch=20"],
    ["--task-count=0"],
    ["--iterations=0"],
    ["--read-count=-1"],
    ["--client-count=-1"],
    ["--client-count=0"],
    ["--control-client-count=-1"],
    ["--control-client-count=0"],
  ])
  func invalidConfigurationThrows(args: [String]) throws {
    #expect(throws: Error.self) {
      let _ = try StorageW1R3.parseAsRoot(["--bucket-name=b"] + args)
    }
  }

  @Test func missingBucketName() throws {
    #expect(throws: Error.self) {
      let _ = try StorageW1R3.parseAsRoot([])
    }
  }
}
