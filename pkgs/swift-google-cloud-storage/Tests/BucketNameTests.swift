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

@Suite struct BucketNameTests {
  @Test(arguments: [
    ("", ""),
    ("my-bucket", "projects/_/buckets/my-bucket"),
    ("projects/_/buckets/my-bucket", "projects/_/buckets/my-bucket"),
  ])
  func formatResourceNameTests(input: String, expected: String) {
    #expect(BucketName.formatResourceName(input) == expected)
    #expect(BucketName.formatBucketResourceName(input) == expected)
    #expect(BucketName.format(input) == expected)
  }

  @Test(arguments: [
    ("", ""),
    ("my-bucket", "my-bucket"),
    ("projects/_/buckets/my-bucket", "my-bucket"),
    ("projects/_/buckets/my-bucket/objects/file.txt", "my-bucket"),
    ("other/prefix/my-bucket", "other/prefix/my-bucket"),
  ])
  func extractBucketNameTests(input: String, expected: String) {
    #expect(BucketName.extractBucketName(input) == expected)
    #expect(BucketName.extract(input) == expected)
  }
}
