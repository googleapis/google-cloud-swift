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

/// A BigQuery ML model.
///
/// Models are created with a `CREATE MODEL` query. The client can read, update, list, and
/// delete them.
///
/// Only ``friendlyName``, ``description``, ``labels``, ``expirationTime``, and
/// ``encryptionConfiguration`` can be changed with
/// ``BigQueryClient/updateModel(_:clearing:selectedFields:ifMatch:options:)``; a `nil`
/// property is left unchanged. The other properties are output only.
public struct Model: Sendable, Hashable {
  /// The model ID. A `nil` project means the client's project.
  public var id: ModelID

  /// A descriptive name.
  public var friendlyName: String?

  /// A user-friendly description.
  public var description: String?

  /// Labels. On update, the given keys are added or changed and other keys are kept.
  public var labels: [String: String]?

  /// When the model expires and is deleted, or `nil` if it never expires.
  public var expirationTime: Date?

  /// The encryption key of the model.
  public var encryptionConfiguration: EncryptionConfiguration?

  /// Output only. The version tag of the model.
  public var etag: String?

  /// Output only. The kind of model.
  public var modelType: ModelType?

  /// Output only. When the model was created.
  public var creationTime: Date?

  /// Output only. When the model was last modified.
  public var lastModifiedTime: Date?

  /// Output only. The geographic location of the model.
  public var location: String?

  /// Output only. Information about each training run, oldest first.
  public var trainingRuns: [TrainingRun]

  /// Output only. The input feature columns used to train the model.
  public var featureColumns: [StandardSQLField]

  /// Output only. The label columns used to train the model. The output of the model has a
  /// `predicted_` prefix on these names.
  public var labelColumns: [StandardSQLField]

  /// Creates a model description, for example to pass to
  /// ``BigQueryClient/updateModel(_:clearing:selectedFields:ifMatch:options:)``.
  public init(
    id: ModelID,
    friendlyName: String? = nil,
    description: String? = nil,
    labels: [String: String]? = nil,
    expirationTime: Date? = nil,
    encryptionConfiguration: EncryptionConfiguration? = nil
  ) {
    self.id = id
    self.friendlyName = friendlyName
    self.description = description
    self.labels = labels
    self.expirationTime = expirationTime
    self.encryptionConfiguration = encryptionConfiguration
    self.trainingRuns = []
    self.featureColumns = []
    self.labelColumns = []
  }

  /// A model property that an update can clear.
  ///
  /// ```swift
  /// try await client.updateModel(Model(id: id), clearing: [.expirationTime, .label("env")])
  /// ```
  public struct Field: Sendable, Hashable {
    /// The JSON path of the property in the request body.
    let path: [String]

    /// ``Model/friendlyName``.
    public static let friendlyName = Field(path: ["friendlyName"])
    /// ``Model/description``.
    public static let description = Field(path: ["description"])
    /// ``Model/expirationTime``: the model no longer expires.
    public static let expirationTime = Field(path: ["expirationTime"])
    /// ``Model/encryptionConfiguration``.
    public static let encryptionConfiguration = Field(path: ["encryptionConfiguration"])
    /// All of ``Model/labels``.
    public static let labels = Field(path: ["labels"])

    /// One label, by key.
    public static func label(_ key: String) -> Field { Field(path: ["labels", key]) }
  }

  /// The kind of a model, for example ``linearRegression``.
  public struct ModelType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The model type as sent by the service.
    public var rawValue: String

    /// Creates a model type from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Linear regression.
    public static let linearRegression = ModelType(rawValue: "LINEAR_REGRESSION")
    /// Logistic regression.
    public static let logisticRegression = ModelType(rawValue: "LOGISTIC_REGRESSION")
    /// K-means clustering.
    public static let kMeans = ModelType(rawValue: "KMEANS")
    /// Matrix factorization.
    public static let matrixFactorization = ModelType(rawValue: "MATRIX_FACTORIZATION")
    /// An imported TensorFlow model.
    public static let tensorFlow = ModelType(rawValue: "TENSORFLOW")
    /// Boosted tree regression.
    public static let boostedTreeRegressor = ModelType(rawValue: "BOOSTED_TREE_REGRESSOR")
    /// Boosted tree classification.
    public static let boostedTreeClassifier = ModelType(rawValue: "BOOSTED_TREE_CLASSIFIER")
    /// ARIMA_PLUS time series forecasting.
    public static let arimaPlus = ModelType(rawValue: "ARIMA_PLUS")

    /// The model type name.
    public var description: String { self.rawValue }
  }

  /// Information about one training run of a model.
  public struct TrainingRun: Sendable, Hashable {
    /// When the training run started.
    public var startTime: Date?

    /// The options the training run used.
    public var trainingOptions: TrainingOptions?

    /// Creates training run information.
    public init(startTime: Date? = nil, trainingOptions: TrainingOptions? = nil) {
      self.startTime = startTime
      self.trainingOptions = trainingOptions
    }
  }

  /// A subset of the options used to train a model.
  public struct TrainingOptions: Sendable, Hashable {
    /// The maximum number of training iterations.
    public var maxIterations: Int64?

    /// The loss function.
    public var lossType: LossType?

    /// The initial learning rate, for ``LearnRateStrategy/constant``.
    public var learnRate: Double?

    /// How the learning rate is chosen.
    public var learnRateStrategy: LearnRateStrategy?

    /// Whether training stops early when the loss stops improving.
    public var earlyStop: Bool?

    /// The column that splits the data into training and evaluation sets.
    public var dataSplitColumn: String?

    /// Creates training options.
    public init(
      maxIterations: Int64? = nil, lossType: LossType? = nil, learnRate: Double? = nil,
      learnRateStrategy: LearnRateStrategy? = nil, earlyStop: Bool? = nil,
      dataSplitColumn: String? = nil
    ) {
      self.maxIterations = maxIterations
      self.lossType = lossType
      self.learnRate = learnRate
      self.learnRateStrategy = learnRateStrategy
      self.earlyStop = earlyStop
      self.dataSplitColumn = dataSplitColumn
    }

    /// A loss function.
    public struct LossType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
      /// The loss type as sent by the service.
      public var rawValue: String

      /// Creates a loss type from its service name.
      public init(rawValue: String) {
        self.rawValue = rawValue
      }

      /// Mean squared loss, for linear regression.
      public static let meanSquaredLoss = LossType(rawValue: "MEAN_SQUARED_LOSS")
      /// Mean log loss, for logistic regression.
      public static let meanLogLoss = LossType(rawValue: "MEAN_LOG_LOSS")

      /// The loss type name.
      public var description: String { self.rawValue }
    }

    /// A learning rate strategy.
    public struct LearnRateStrategy: RawRepresentable, Sendable, Hashable,
      CustomStringConvertible
    {
      /// The strategy as sent by the service.
      public var rawValue: String

      /// Creates a strategy from its service name.
      public init(rawValue: String) {
        self.rawValue = rawValue
      }

      /// Line search for the learning rate in each iteration.
      public static let lineSearch = LearnRateStrategy(rawValue: "LINE_SEARCH")
      /// A constant learning rate.
      public static let constant = LearnRateStrategy(rawValue: "CONSTANT")

      /// The strategy name.
      public var description: String { self.rawValue }
    }
  }
}
