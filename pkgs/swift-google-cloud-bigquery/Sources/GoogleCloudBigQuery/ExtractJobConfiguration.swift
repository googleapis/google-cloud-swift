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

import GoogleCloudBigQueryV2

/// The compression of extracted files.
public struct ExtractCompression: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let none = ExtractCompression(rawValue: "NONE")
  public static let gzip = ExtractCompression(rawValue: "GZIP")
  public static let deflate = ExtractCompression(rawValue: "DEFLATE")
  public static let snappy = ExtractCompression(rawValue: "SNAPPY")
  public static let zstd = ExtractCompression(rawValue: "ZSTD")

  public var description: String { self.rawValue }
}

extension DataFormat {
  /// A TensorFlow SavedModel, for extracting models.
  public static let mlTFSavedModel = DataFormat(rawValue: "ML_TF_SAVED_MODEL")
  /// An XGBoost Booster, for extracting models.
  public static let mlXGBoostBooster = DataFormat(rawValue: "ML_XGBOOST_BOOSTER")
}

/// The configuration of an extract job, which exports a table or a model to Cloud Storage.
public struct ExtractJobConfiguration: Sendable, Equatable {
  /// What an extract job exports.
  public struct Source: Sendable, Hashable {
    enum Storage: Hashable {
      case table(TableID)
      case model(ModelID)
    }

    var storage: Storage

    /// Exports a table.
    public static func table(_ id: TableID) -> Source {
      Source(storage: .table(id))
    }

    /// Exports a model.
    public static func model(_ id: ModelID) -> Source {
      Source(storage: .model(id))
    }

    /// The table, if the source is a table.
    public var table: TableID? {
      if case .table(let id) = self.storage { return id }
      return nil
    }

    /// The model, if the source is a model.
    public var model: ModelID? {
      if case .model(let id) = self.storage { return id }
      return nil
    }
  }

  /// The table or model to export.
  public var source: Source
  /// The Cloud Storage URIs to write, for example `gs://bucket/file-*.csv`.
  public var destinationURIs: [String]
  /// The format of the files. The service default is CSV for tables.
  public var format: DataFormat?
  /// The compression of the files.
  public var compression: ExtractCompression?
  /// Whether CSV files have a header row. The service default is `true`.
  public var printHeader: Bool?
  /// The CSV field delimiter. The service default is `,`.
  public var fieldDelimiter: String?
  /// Whether Avro files use logical types.
  public var useAvroLogicalTypes: Bool?
  /// The trial of a hyperparameter-tuned model to export.
  public var modelTrialID: Int64?
  /// Labels for the job.
  public var labels: [String: String]
  /// The maximum time the job may run.
  public var jobTimeout: Duration?
  /// The reservation that runs the job.
  public var reservation: String?

  /// Creates an extract configuration.
  public init(source: Source, destinationURIs: [String], format: DataFormat? = nil) {
    self.source = source
    self.destinationURIs = destinationURIs
    self.format = format
    self.labels = [:]
  }

  var common: CommonJobFields {
    CommonJobFields(labels: self.labels, jobTimeout: self.jobTimeout, reservation: self.reservation)
  }
}

// MARK: - Wire conversion

extension ExtractJobConfiguration {
  init(
    wire: GoogleCloudBigQueryV2.JobConfigurationExtract,
    common: GoogleCloudBigQueryV2.JobConfiguration
  ) {
    let source: Source
    switch wire.source {
    case .sourceModel(let model): source = .model(ModelID(wire: model))
    case .sourceTable(let table): source = .table(TableID(wire: table))
    case nil: source = .table(TableID(datasetID: "", tableID: ""))
    }
    self.init(
      source: source, destinationURIs: wire.destinationUris,
      format: wire.destinationFormat.nonEmpty.map(DataFormat.init(rawValue:)))
    self.compression = wire.compression.nonEmpty.map(ExtractCompression.init(rawValue:))
    self.printHeader = wire.printHeader
    self.fieldDelimiter = wire.fieldDelimiter.nonEmpty
    self.useAvroLogicalTypes = wire.useAvroLogicalTypes
    self.modelTrialID = wire.modelExtractOptions?.trialId
    let shared = CommonJobFields(wire: common)
    self.labels = shared.labels
    self.jobTimeout = shared.jobTimeout
    self.reservation = shared.reservation
  }

  var wire: GoogleCloudBigQueryV2.JobConfigurationExtract {
    GoogleCloudBigQueryV2.JobConfigurationExtract().with {
      switch self.source.storage {
      case .table(let id): $0.source = .sourceTable(id.wire)
      case .model(let id): $0.source = .sourceModel(id.wire)
      }
      $0.destinationUris = self.destinationURIs
      $0.destinationFormat = self.format?.rawValue ?? ""
      $0.compression = self.compression?.rawValue ?? ""
      $0.printHeader = self.printHeader
      $0.fieldDelimiter = self.fieldDelimiter ?? ""
      $0.useAvroLogicalTypes = self.useAvroLogicalTypes
      if let trial = self.modelTrialID {
        $0.modelExtractOptions = GoogleCloudBigQueryV2.JobConfigurationExtract.ModelExtractOptions()
          .with { $0.trialId = trial }
      }
    }
  }

  func withDefaultProject(_ projectID: String) -> ExtractJobConfiguration {
    var copy = self
    switch copy.source.storage {
    case .table(let id): copy.source = .table(id.withDefaultProject(projectID))
    case .model(let id): copy.source = .model(id.withDefaultProject(projectID))
    }
    return copy
  }
}
