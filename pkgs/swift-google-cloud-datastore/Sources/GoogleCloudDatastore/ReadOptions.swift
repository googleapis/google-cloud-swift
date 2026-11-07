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

public import GoogleGax
public import GoogleWKT

/// Read consistency mode for non-transactional Datastore reads.
public enum ReadConsistency: Sendable, Hashable {
  /// Strongly consistent reads (`ReadConsistency.STRONG`).
  case strong
  /// Eventually consistent reads (`ReadConsistency.EVENTUAL`).
  case eventual
}

/// Options controlling read consistency, snapshot timestamp, and property masking.
public struct ReadOptions: Sendable {
  /// Mutually exclusive consistency selector (`consistency_type` oneof on the wire).
  public enum ConsistencySelector: Sendable, Hashable {
    /// Uses strong or eventual read consistency.
    case consistency(ReadConsistency)
    /// Reads entities from a consistent snapshot at the given UTC timestamp (`read_time`).
    case readTime(GoogleWKT.WKTTimestamp)
  }

  /// The consistency or snapshot timestamp selector. Defaults to `nil` (server default: `.strong`).
  public var selector: ConsistencySelector?

  /// Optional list of property paths to return (`PropertyMask`). If `nil`, all properties are returned.
  public var propertyMask: [String]?

  /// Per-request HTTP / retry options.
  public var requestOptions: GoogleGax.RequestOptions?

  /// Creates `ReadOptions`.
  public init(
    selector: ConsistencySelector? = nil,
    propertyMask: [String]? = nil,
    requestOptions: GoogleGax.RequestOptions? = nil
  ) {
    self.selector = selector
    self.propertyMask = propertyMask
    self.requestOptions = requestOptions
  }

  /// Convenience factory for `ReadOptions` with a `ReadConsistency`.
  public static func consistency(
    _ consistency: ReadConsistency,
    propertyMask: [String]? = nil,
    requestOptions: GoogleGax.RequestOptions? = nil
  ) -> Self {
    Self(
      selector: .consistency(consistency),
      propertyMask: propertyMask,
      requestOptions: requestOptions
    )
  }

  /// Convenience factory for `ReadOptions` reading from a snapshot `readTime`.
  public static func readTime(
    _ readTime: GoogleWKT.WKTTimestamp,
    propertyMask: [String]? = nil,
    requestOptions: GoogleGax.RequestOptions? = nil
  ) -> Self {
    Self(
      selector: .readTime(readTime),
      propertyMask: propertyMask,
      requestOptions: requestOptions
    )
  }
}
