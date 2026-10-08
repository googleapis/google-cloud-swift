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

public import Foundation

/// A BigQuery dataset: a container for tables, views, routines, and models.
///
/// Properties that are `nil` are not sent to the service. On
/// ``BigQueryClient/updateDataset(_:clearing:updateMode:accessPolicyVersion:selectedFields:ifMatch:options:)``
/// a `nil` property is left unchanged; use the `clearing` parameter to remove a value.
///
/// The output-only properties (``etag``, ``generatedID``, ``selfLink``, ``creationTime``, and
/// ``lastModifiedTime``) are set by the service and ignored on create and update.
///
/// ``BigQueryClient/listDatasets(projectID:all:filter:pageSize:pageToken:options:)`` returns
/// partial datasets: only ``id``, ``friendlyName``, ``location``, ``labels``,
/// ``externalDatasetReference``, and ``generatedID`` are set.
public struct Dataset: Sendable, Hashable {
  /// The dataset ID. A `nil` project means the client's project.
  public var id: DatasetID

  /// A descriptive name.
  public var friendlyName: String?

  /// A user-friendly description.
  public var description: String?

  /// The geographic location, for example `US` or `europe-west1`. Set on create only; when
  /// `nil` the service default is used.
  public var location: String?

  /// Labels. On update, the given keys are added or changed and other keys are kept.
  public var labels: [String: String]?

  /// The default lifetime of new tables in the dataset (minimum one hour, millisecond
  /// precision).
  public var defaultTableExpiration: Duration?

  /// The default partition expiration of new partitioned tables in the dataset (millisecond
  /// precision).
  public var defaultPartitionExpiration: Duration?

  /// The access control list. On update, the list replaces the existing one.
  public var access: [Acl]?

  /// The default encryption key for new tables in the dataset.
  public var defaultEncryptionConfiguration: EncryptionConfiguration?

  /// The default collation of new tables in the dataset, for example `und:ci`.
  public var defaultCollation: String?

  /// The time travel window, in hours. Must be a multiple of 24 between 48 and 168.
  public var maxTimeTravelHours: Int64?

  /// The storage billing model.
  public var storageBillingModel: StorageBillingModel?

  /// Whether table and dataset names in the dataset are case-insensitive.
  public var isCaseInsensitive: Bool?

  /// Resource Manager tags, keyed by namespaced tag key (for example `12345/environment`) with
  /// short tag values.
  public var resourceTags: [String: String]?

  /// The external source backing the dataset, for federated datasets.
  public var externalDatasetReference: ExternalDatasetReference?

  /// Output only. The version tag of the dataset's metadata.
  public var etag: String?

  /// Output only. The fully qualified ID, `project:dataset`.
  public var generatedID: String?

  /// Output only. A URL for the dataset resource.
  public var selfLink: String?

  /// Output only. When the dataset was created.
  public var creationTime: Date?

  /// Output only. When the dataset or any of its tables was last modified.
  public var lastModifiedTime: Date?

  /// Creates a dataset description, for example to pass to
  /// ``BigQueryClient/createDataset(_:accessPolicyVersion:selectedFields:options:)``.
  public init(
    id: DatasetID,
    friendlyName: String? = nil,
    description: String? = nil,
    location: String? = nil,
    labels: [String: String]? = nil,
    defaultTableExpiration: Duration? = nil,
    defaultPartitionExpiration: Duration? = nil,
    access: [Acl]? = nil,
    defaultEncryptionConfiguration: EncryptionConfiguration? = nil,
    defaultCollation: String? = nil,
    maxTimeTravelHours: Int64? = nil,
    storageBillingModel: StorageBillingModel? = nil,
    isCaseInsensitive: Bool? = nil,
    resourceTags: [String: String]? = nil,
    externalDatasetReference: ExternalDatasetReference? = nil
  ) {
    self.id = id
    self.friendlyName = friendlyName
    self.description = description
    self.location = location
    self.labels = labels
    self.defaultTableExpiration = defaultTableExpiration
    self.defaultPartitionExpiration = defaultPartitionExpiration
    self.access = access
    self.defaultEncryptionConfiguration = defaultEncryptionConfiguration
    self.defaultCollation = defaultCollation
    self.maxTimeTravelHours = maxTimeTravelHours
    self.storageBillingModel = storageBillingModel
    self.isCaseInsensitive = isCaseInsensitive
    self.resourceTags = resourceTags
    self.externalDatasetReference = externalDatasetReference
  }

  /// A dataset property that an update can clear.
  ///
  /// ```swift
  /// try await client.updateDataset(dataset, clearing: [.description, .label("env")])
  /// ```
  public struct Field: Sendable, Hashable {
    /// The segments of the property's JSON path in the request body. A segment may contain
    /// `.`, for example a resource tag key.
    let path: [String]

    /// ``Dataset/friendlyName``.
    public static let friendlyName = Field(path: ["friendlyName"])
    /// ``Dataset/description``.
    public static let description = Field(path: ["description"])
    /// ``Dataset/defaultTableExpiration``.
    public static let defaultTableExpiration = Field(path: ["defaultTableExpirationMs"])
    /// ``Dataset/defaultPartitionExpiration``.
    public static let defaultPartitionExpiration = Field(path: ["defaultPartitionExpirationMs"])
    /// ``Dataset/defaultEncryptionConfiguration``.
    public static let defaultEncryptionConfiguration = Field(
      path: ["defaultEncryptionConfiguration"])
    /// ``Dataset/defaultCollation``.
    public static let defaultCollation = Field(path: ["defaultCollation"])
    /// All of ``Dataset/labels``.
    public static let labels = Field(path: ["labels"])
    /// All of ``Dataset/resourceTags``.
    public static let resourceTags = Field(path: ["resourceTags"])

    /// One label, by key.
    public static func label(_ key: String) -> Field { Field(path: ["labels", key]) }

    /// One resource tag, by namespaced tag key, for example `12345/environment`.
    public static func resourceTag(_ key: String) -> Field {
      Field(path: ["resourceTags", key])
    }
  }

  /// How a dataset's storage is billed.
  public struct StorageBillingModel: RawRepresentable, Sendable, Hashable,
    CustomStringConvertible
  {
    /// The billing model as sent to the service.
    public var rawValue: String

    /// Creates a billing model from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Billed by logical (uncompressed) bytes.
    public static let logical = StorageBillingModel(rawValue: "LOGICAL")
    /// Billed by physical (compressed) bytes, including time travel storage.
    public static let physical = StorageBillingModel(rawValue: "PHYSICAL")

    /// The billing model name.
    public var description: String { self.rawValue }
  }
}

/// The external source that backs a federated dataset.
public struct ExternalDatasetReference: Sendable, Hashable {
  /// The external source, for example
  /// `google-cloudspanner:/projects/p/instances/i/databases/d`.
  public var externalSource: String

  /// The connection used to access the external source, in the form
  /// `projects/{project}/locations/{location}/connections/{connection}`.
  public var connection: String

  /// Creates an external dataset reference.
  public init(externalSource: String, connection: String) {
    self.externalSource = externalSource
    self.connection = connection
  }
}

/// Which parts of a dataset ``BigQueryClient/getDataset(_:view:accessPolicyVersion:selectedFields:options:)``
/// returns.
public struct DatasetView: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  /// The view as sent to the service.
  public var rawValue: String

  /// Creates a view from its service name.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Metadata only, without the access control list.
  public static let metadata = DatasetView(rawValue: "METADATA")
  /// The access control list only.
  public static let acl = DatasetView(rawValue: "ACL")
  /// Metadata and the access control list.
  public static let full = DatasetView(rawValue: "FULL")

  /// The view name.
  public var description: String { self.rawValue }
}

/// Which parts of a dataset
/// ``BigQueryClient/updateDataset(_:clearing:updateMode:accessPolicyVersion:selectedFields:ifMatch:options:)``
/// changes.
public struct DatasetUpdateMode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  /// The mode as sent to the service.
  public var rawValue: String

  /// Creates a mode from its service name.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Metadata only; the access control list is not changed.
  public static let updateMetadata = DatasetUpdateMode(rawValue: "UPDATE_METADATA")
  /// The access control list only.
  public static let updateACL = DatasetUpdateMode(rawValue: "UPDATE_ACL")
  /// Metadata and the access control list.
  public static let updateFull = DatasetUpdateMode(rawValue: "UPDATE_FULL")

  /// The mode name.
  public var description: String { self.rawValue }
}
