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

  @Test func grpcTypealiasCompatibility() {
    let segment: GoogleCloudGaxGRPC._RoutingSegment = .literal("test")
    #expect(segment == GoogleCloudGax._RoutingSegment.literal("test"))
    #expect(GoogleCloudGaxGRPC._RoutingMatcher.encode("foo/bar") == "foo%2Fbar")
  }

  @Test func restUriPercentEncoding() {
    // Unreserved set per go/client-libraries:rest-special-uri-chars: [-_.~/0-9a-zA-Z]
    #expect(
      _RoutingMatcher.encodePath("abcdefghijklmnopqrstuvwxyz") == "abcdefghijklmnopqrstuvwxyz"
    )
    #expect(
      _RoutingMatcher.encodePath("ABCDEFGHIJKLMNOPQRSTUVWXYZ") == "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    )
    #expect(_RoutingMatcher.encodePath("0123456789") == "0123456789")
    #expect(_RoutingMatcher.encodePath("-._~") == "-._~")
    // Slashes are preserved
    #expect(_RoutingMatcher.encodePath("a/b/c/d") == "a/b/c/d")

    // Reserved and query injection characters are percent-encoded
    #expect(_RoutingMatcher.encodePath("hello world") == "hello%20world")
    #expect(_RoutingMatcher.encodePath("foo?bar=1&baz=2") == "foo%3Fbar%3D1%26baz%3D2")
    #expect(_RoutingMatcher.encodePath("projects/p:start") == "projects/p%3Astart")
    #expect(_RoutingMatcher.encodePath("topics/t#fragment") == "topics/t%23fragment")
    #expect(_RoutingMatcher.encodePath("bucket+name") == "bucket%2Bname")
    #expect(_RoutingMatcher.encodePath("user@host") == "user%40host")
    #expect(_RoutingMatcher.encodePath("item;matrix") == "item%3Bmatrix")
  }

  @Test func validateSingleSegmentRules() throws {
    // Valid single segments pass
    try _RoutingMatcher.validateSingleSegment(value: "us-central1", fieldName: "location")
    try _RoutingMatcher.validateSingleSegment(value: ".hidden", fieldName: "location")
    try _RoutingMatcher.validateSingleSegment(value: "..hidden", fieldName: "location")
    try _RoutingMatcher.validateSingleSegment(value: "my.segment", fieldName: "location")

    // "." and ".." throw structured RequestError.binding
    #expect(throws: RequestError.self) {
      try _RoutingMatcher.validateSingleSegment(value: ".", fieldName: "location")
    }
    #expect(throws: RequestError.self) {
      try _RoutingMatcher.validateSingleSegment(value: "..", fieldName: "location")
    }

    do {
      try _RoutingMatcher.validateSingleSegment(value: ".", fieldName: "location")
    } catch let RequestError.binding(err) {
      #expect(err.description == "Invalid value . for location")
    }

    do {
      try _RoutingMatcher.validateSingleSegment(value: "..", fieldName: "parent")
    } catch let RequestError.binding(err) {
      #expect(err.description == "Invalid value .. for parent")
    }
  }

  @Test func validateMultiSegmentRules() throws {
    // Valid multi-segments pass
    try _RoutingMatcher.validateMultiSegment(value: "projects/p/topics/t", fieldName: "name")
    try _RoutingMatcher.validateMultiSegment(value: ".hidden/sub..dir", fieldName: "name")
    try _RoutingMatcher.validateMultiSegment(value: "domain.com/path", fieldName: "name")

    // Segments that are exactly "." or ".." throw RequestError.binding
    let badPaths = [
      ".",
      "..",
      "./foo",
      "../foo",
      "foo/.",
      "foo/..",
      "foo/./bar",
      "foo/../bar",
      "foo///../bar",
    ]

    for badPath in badPaths {
      #expect(throws: RequestError.self) {
        try _RoutingMatcher.validateMultiSegment(value: badPath, fieldName: "name")
      }
    }

    do {
      try _RoutingMatcher.validateMultiSegment(value: "projects/p/topics/a/../b", fieldName: "name")
    } catch let RequestError.binding(err) {
      #expect(
        err.description == "Value for name must not contain segments that are exactly . or ..")
    }
  }

  @Test func pathValueSingleWildcard() throws {
    // Structural match and encoding
    let matched = try _RoutingMatcher.pathValue(
      "projects/p1/locations/us-central1",
      matching: [.literal("projects/"), .singleWildcard, .literal("/locations/"), .singleWildcard],
      fieldName: "name"
    )
    #expect(matched == "projects/p1/locations/us-central1")

    // Special characters are percent-encoded
    let withSpaces = try _RoutingMatcher.pathValue(
      "projects/my project/locations/us central1",
      matching: [.literal("projects/"), .singleWildcard, .literal("/locations/"), .singleWildcard],
      fieldName: "name"
    )
    #expect(withSpaces == "projects/my%20project/locations/us%20central1")

    // Structural mismatch returns nil
    let mismatch = try _RoutingMatcher.pathValue(
      "organizations/123/locations/us",
      matching: [.literal("projects/"), .singleWildcard, .literal("/locations/"), .singleWildcard],
      fieldName: "name"
    )
    #expect(mismatch == nil)

    // Empty or nil returns nil
    #expect(
      try _RoutingMatcher.pathValue(nil, matching: [.singleWildcard], fieldName: "name") == nil)
    #expect(
      try _RoutingMatcher.pathValue("", matching: [.singleWildcard], fieldName: "name") == nil)

    // Dot violations throw
    #expect(throws: RequestError.self) {
      try _RoutingMatcher.pathValue(
        "projects/./locations/us",
        matching: [
          .literal("projects/"), .singleWildcard, .literal("/locations/"), .singleWildcard,
        ],
        fieldName: "name"
      )
    }

    #expect(throws: RequestError.self) {
      try _RoutingMatcher.pathValue(
        "projects/p/locations/..",
        matching: [
          .literal("projects/"), .singleWildcard, .literal("/locations/"), .singleWildcard,
        ],
        fieldName: "name"
      )
    }
  }

  @Test func pathValueMultiWildcard() throws {
    // Valid multi-segment wildcard
    let matched = try _RoutingMatcher.pathValue(
      "projects/p/topics/a/b/c",
      matching: [.literal("projects/"), .singleWildcard, .literal("/topics/"), .multiWildcard],
      fieldName: "name"
    )
    #expect(matched == "projects/p/topics/a/b/c")

    // Multi-segment with special characters
    let encoded = try _RoutingMatcher.pathValue(
      "projects/p/topics/a/b?param=1/c",
      matching: [.literal("projects/"), .singleWildcard, .literal("/topics/"), .multiWildcard],
      fieldName: "name"
    )
    #expect(encoded == "projects/p/topics/a/b%3Fparam%3D1/c")

    // Multi-segment dot violation throws
    #expect(throws: RequestError.self) {
      try _RoutingMatcher.pathValue(
        "projects/p/topics/a/../c",
        matching: [.literal("projects/"), .singleWildcard, .literal("/topics/"), .multiWildcard],
        fieldName: "name"
      )
    }
  }
}
