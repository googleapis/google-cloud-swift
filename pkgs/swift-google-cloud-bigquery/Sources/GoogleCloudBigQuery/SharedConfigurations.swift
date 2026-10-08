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

/// Customer-managed encryption for a dataset, table, or job destination.
public struct EncryptionConfiguration: Sendable, Hashable {
  /// The Cloud KMS key, for example
  /// `projects/p/locations/l/keyRings/r/cryptoKeys/k`.
  public var kmsKeyName: String?

  /// Creates an encryption configuration.
  public init(kmsKeyName: String? = nil) {
    self.kmsKeyName = kmsKeyName
  }
}

/// Partitions a table by a time unit.
public struct TimePartitioning: Sendable, Hashable {
  /// The granularity of a time-partitioned table.
  public struct PartitionType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public static let hour = PartitionType(rawValue: "HOUR")
    public static let day = PartitionType(rawValue: "DAY")
    public static let month = PartitionType(rawValue: "MONTH")
    public static let year = PartitionType(rawValue: "YEAR")

    public var description: String { self.rawValue }
  }

  /// The partition granularity.
  public var type: PartitionType

  /// The column used for partitioning, or `nil` to partition by ingestion time.
  public var field: String?

  /// How long to keep the storage for each partition, in milliseconds precision.
  public var expiration: Duration?

  /// Creates a time-partitioning specification.
  public init(type: PartitionType, field: String? = nil, expiration: Duration? = nil) {
    self.type = type
    self.field = field
    self.expiration = expiration
  }
}

/// Partitions a table by ranges of an integer column.
public struct RangePartitioning: Sendable, Hashable {
  /// The integer ranges of the partitions.
  public struct Range: Sendable, Hashable {
    /// The start of the first partition, inclusive.
    public var start: Int64
    /// The end of the last partition, exclusive.
    public var end: Int64
    /// The width of each partition.
    public var interval: Int64

    /// Creates a range.
    public init(start: Int64, end: Int64, interval: Int64) {
      self.start = start
      self.end = end
      self.interval = interval
    }
  }

  /// The `INT64` column used for partitioning.
  public var field: String

  /// The partition ranges.
  public var range: Range

  /// Creates a range-partitioning specification.
  public init(field: String, range: Range) {
    self.field = field
    self.range = range
  }
}

/// Clusters the data of a table by up to four columns.
public struct Clustering: Sendable, Hashable {
  /// The clustering columns, in order.
  public var fields: [String]

  /// Creates a clustering specification.
  public init(fields: [String]) {
    self.fields = fields
  }
}

/// Whether running a query may skip creating a job.
public struct JobCreationMode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Always create a job.
  public static let required = JobCreationMode(rawValue: "JOB_CREATION_REQUIRED")

  /// Let the service run short queries without creating a job.
  ///
  /// Results of such queries have a query ID but no job ID.
  public static let optional = JobCreationMode(rawValue: "JOB_CREATION_OPTIONAL")

  public var description: String { self.rawValue }
}

/// A JavaScript user-defined function resource, used by legacy SQL views and queries.
public enum UserDefinedFunction: Sendable, Hashable {
  /// The function's code, inline.
  case inline(String)

  /// A Cloud Storage URI (`gs://bucket/path`) of a file that contains the function's code.
  case fromURI(String)
}
