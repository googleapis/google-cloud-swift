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
@_spi(GoogleCloudInternal) import GoogleCloudGaxGRPC
import Testing

@Suite struct RoutingMatcherTests {
  @Test func rfc6570PercentEncoding() {
    // RFC 6570 Section 1.5 unreserved: ALPHA / DIGIT / - / . / _ / ~
    #expect(_RoutingMatcher.encode("abcdefghijklmnopqrstuvwxyz") == "abcdefghijklmnopqrstuvwxyz")
    #expect(_RoutingMatcher.encode("ABCDEFGHIJKLMNOPQRSTUVWXYZ") == "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    #expect(_RoutingMatcher.encode("0123456789") == "0123456789")
    #expect(_RoutingMatcher.encode("-._~") == "-._~")

    // Slashes and other reserved/special characters must be encoded
    #expect(_RoutingMatcher.encode("foo/bar") == "foo%2Fbar")
    #expect(
      _RoutingMatcher.encode("projects/_/buckets/my-bucket") == "projects%2F_%2Fbuckets%2Fmy-bucket"
    )
    #expect(_RoutingMatcher.encode("foo=bar&baz=qux") == "foo%3Dbar%26baz%3Dqux")
    #expect(_RoutingMatcher.encode("hello world") == "hello%20world")
  }

  @Test func formatKeyValue() {
    #expect(
      _RoutingMatcher.format(key: "bucket", value: "projects/_/buckets/my-bucket")
        == "bucket=projects%2F_%2Fbuckets%2Fmy-bucket"
    )
    #expect(
      _RoutingMatcher.format(key: "table/name", value: "a/b/c")
        == "table%2Fname=a%2Fb%2Fc"
    )
  }

  @Test func formatList() {
    let params = _RoutingMatcher.format([
      ("bucket", "projects/_/buckets/d"),
      ("empty", nil),
      ("source_bucket", "projects/_/buckets/s"),
      ("blank", ""),
    ])
    #expect(
      params == [
        "bucket=projects%2F_%2Fbuckets%2Fd",
        "source_bucket=projects%2F_%2Fbuckets%2Fs",
      ])
  }

  @Test func matchEntireMultiWildcard() {
    let match = _RoutingMatcher.value(
      "projects/my-project/buckets/my-bucket",
      matching: [.multiWildcard]
    )
    #expect(match == "projects/my-project/buckets/my-bucket")
  }

  @Test func matchPrefixAndSingleWildcard() {
    let match = _RoutingMatcher.value(
      "projects/my-project/locations/us-central1",
      prefix: [.literal("projects/"), .singleWildcard, .literal("/locations/")],
      matching: [.singleWildcard]
    )
    #expect(match == "us-central1")
  }

  @Test func matchGcsBucketWithTrailingWildcard() {
    // Pattern: {bucket=projects/*/buckets/*}/** on "projects/p/buckets/b/folders/f"
    let match1 = _RoutingMatcher.value(
      "projects/my-proj/buckets/test-bucket/folders/my-folder",
      matching: [
        .literal("projects/"),
        .singleWildcard,
        .literal("/buckets/"),
        .singleWildcard,
      ],
      suffix: [.trailingMultiWildcard]
    )
    #expect(match1 == "projects/my-proj/buckets/test-bucket")

    // Without trailing path segments
    let match2 = _RoutingMatcher.value(
      "projects/_/buckets/test-bucket",
      matching: [
        .literal("projects/"),
        .singleWildcard,
        .literal("/buckets/"),
        .singleWildcard,
      ],
      suffix: [.trailingMultiWildcard]
    )
    #expect(match2 == "projects/_/buckets/test-bucket")

    // With storageLayout suffix
    let match3 = _RoutingMatcher.value(
      "projects/_/buckets/test-bucket/storageLayout",
      matching: [
        .literal("projects/"),
        .singleWildcard,
        .literal("/buckets/"),
        .singleWildcard,
      ],
      suffix: [.trailingMultiWildcard]
    )
    #expect(match3 == "projects/_/buckets/test-bucket")
  }

  @Test func matchWithPrefixAndSuffix() {
    // projects/p/locations/l/instances/i/tables/t
    let match = _RoutingMatcher.value(
      "projects/p/locations/l/instances/i/tables/t",
      prefix: [
        .literal("projects/"),
        .singleWildcard,
        .literal("/locations/"),
        .singleWildcard,
        .literal("/"),
      ],
      matching: [
        .literal("instances/"),
        .singleWildcard,
      ],
      suffix: [
        .literal("/tables"),
        .trailingMultiWildcard,
      ]
    )
    #expect(match == "instances/i")
  }

  @Test func matchMismatchCases() {
    #expect(_RoutingMatcher.value(nil, matching: [.multiWildcard]) == nil)
    #expect(_RoutingMatcher.value("", matching: [.multiWildcard]) == nil)

    // Prefix mismatch
    #expect(
      _RoutingMatcher.value(
        "organizations/123/locations/us",
        prefix: [.literal("projects/"), .singleWildcard, .literal("/locations/")],
        matching: [.singleWildcard]
      ) == nil
    )

    // Suffix mismatch
    #expect(
      _RoutingMatcher.value(
        "projects/p/locations/us/extra",
        prefix: [.literal("projects/"), .singleWildcard, .literal("/locations/")],
        matching: [.singleWildcard],
        suffix: [.literal("/zones/z")]
      ) == nil
    )
  }

  @Test func fallbackChaining() {
    let reqName: String? = "invalid-name"
    let reqParent: String? = "projects/p/buckets/b"

    let extracted =
      _RoutingMatcher.value(
        reqName,
        prefix: [.literal("projects/"), .singleWildcard, .literal("/locations/")],
        matching: [.singleWildcard]
      )
      ?? _RoutingMatcher.value(
        reqParent,
        matching: [.multiWildcard]
      )

    #expect(extracted == "projects/p/buckets/b")
  }
}
