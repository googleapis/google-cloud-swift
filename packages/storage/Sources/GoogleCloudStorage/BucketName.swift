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

/// Utility class for working with Google Cloud Storage bucket resource names and identifiers.
package final class BucketName: Sendable {
  private init() {}

  /// Formats a bucket name or resource path into the canonical resource name format
  /// (`projects/_/buckets/<bucket>`).
  ///
  /// If `bucket` is empty, this returns an empty string. If `bucket` is already in a
  /// `projects/...` format, it is returned unmodified. Otherwise, `projects/_/buckets/`
  /// is prepended.
  package static func formatResourceName(_ bucket: String) -> String {
    guard !bucket.isEmpty else { return "" }
    if bucket.hasPrefix("projects/") {
      return bucket
    }
    return "projects/_/buckets/\(bucket)"
  }

  /// Formats a project and bucket name into the canonical resource name format
  /// (`projects/<project>/buckets/<bucket>`).
  package static func format(project: String = "_", bucket: String) -> String {
    guard !bucket.isEmpty else { return "" }
    let proj = project.isEmpty ? "_" : project
    return "projects/\(proj)/buckets/\(bucket)"
  }

  /// Alias for `formatResourceName(_:)`.
  package static func formatBucketResourceName(_ bucket: String) -> String {
    formatResourceName(bucket)
  }

  /// Alias for `formatResourceName(_:)`.
  package static func format(_ bucket: String) -> String {
    formatResourceName(bucket)
  }

  /// Extracts the simple bucket name from a bucket resource name or plain bucket name.
  ///
  /// If `bucket` is in a format such as `projects/_/buckets/<bucket>` or `projects/<project>/buckets/<bucket>`,
  /// this returns `<bucket>`. Otherwise, it returns `bucket` as-is.
  package static func extractBucketName(_ bucket: String) -> String {
    guard !bucket.isEmpty else { return "" }
    if bucket.hasPrefix("projects/") {
      if let range = bucket.range(of: "/buckets/") {
        let remainder = bucket[range.upperBound...]
        if let slashIndex = remainder.firstIndex(of: "/") {
          return String(remainder[..<slashIndex])
        }
        return String(remainder)
      }
    }
    return bucket
  }

  /// Alias for `extractBucketName(_:)`.
  package static func extract(_ bucket: String) -> String {
    extractBucketName(bucket)
  }

  /// Extracts the project ID or number from a bucket resource name, if present.
  ///
  /// For example, given `projects/12345/buckets/my-bucket`, returns `"12345"`.
  /// If the string is not a resource name or does not contain a project, returns `nil`.
  package static func extractProject(_ bucket: String) -> String? {
    guard bucket.hasPrefix("projects/") else { return nil }
    let remainder = bucket.dropFirst("projects/".count)
    guard let slashIndex = remainder.firstIndex(of: "/") else { return nil }
    let project = String(remainder[..<slashIndex])
    return project.isEmpty ? nil : project
  }
}
