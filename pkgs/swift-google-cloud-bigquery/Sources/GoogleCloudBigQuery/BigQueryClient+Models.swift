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
import GoogleCloudBigQueryV2
public import GoogleGax

extension BigQueryClient {
  /// Returns a model, or `nil` if it does not exist.
  ///
  /// - Parameters:
  ///   - id: the model. A `nil` project means the client's project.
  ///   - selectedFields: the model fields to return, for example `["labels"]`. The ID is always
  ///     returned.
  ///   - options: per-call options.
  public func getModel(
    _ id: ModelID,
    selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Model? {
    let request = HTTPRequest(
      method: .get, path: self.resolve(id).resourcePath,
      query: SelectedFields.query(selectedFields, required: Self.modelRequiredFields),
      options: options)
    return try await self.transport.jsonOrNil(request, as: GoogleCloudBigQueryV2.Model.self)
      .map(Model.init(wire:))
  }

  /// Lists the models in a dataset.
  ///
  /// The models are partial: the service omits training runs and columns. Use
  /// ``getModel(_:selectedFields:options:)`` for the full resource.
  ///
  /// - Parameters:
  ///   - dataset: the dataset. A `nil` project means the client's project.
  ///   - pageSize: the maximum number of models per page, or `nil` for the service default.
  ///   - pageToken: the page to start from, from ``Page/nextPageToken``.
  ///   - options: per-call options, applied to every page request.
  public func listModels(
    in dataset: DatasetID,
    pageSize: Int? = nil,
    pageToken: String? = nil,
    options: RequestOptions = .init()
  ) -> PagedSequence<Model> {
    let path = self.resolve(dataset).resourcePath + "/models"
    return PagedSequence { [transport] token in
      let list: ListModelsResponse = try await transport.json(
        HTTPRequest(
          method: .get, path: path, query: ResourcePaging.query(pageSize, token ?? pageToken),
          options: options),
        idempotent: true)
      return Page(
        items: list.models.map(Model.init(wire:)), nextPageToken: list.nextPageToken.nonEmpty)
    }
  }

  /// Updates a model with the non-`nil` mutable properties of `model` (HTTP PATCH).
  ///
  /// `nil` properties are left unchanged and ``Model/labels`` are merged into the existing
  /// labels. To remove a value, name it in `clearing`; clearing takes precedence over a value
  /// set in `model`. Output-only properties are ignored.
  ///
  /// ```swift
  /// try await client.updateModel(
  ///   Model(id: id, description: "Churn model v2"), clearing: [.expirationTime])
  /// ```
  ///
  /// The request is retried only when `etag` is given, because a retried PATCH could
  /// otherwise overwrite a concurrent change.
  ///
  /// - Parameters:
  ///   - model: the model ID and the properties to change.
  ///   - clearing: the properties to remove.
  ///   - selectedFields: the model fields to return. The ID is always returned.
  ///   - etag: update only if the model's current ``Model/etag`` matches (`If-Match`).
  ///     A mismatch fails with HTTP 412.
  ///   - options: per-call options.
  /// - Returns: the updated model.
  public func updateModel(
    _ model: Model,
    clearing: Set<Model.Field> = [],
    selectedFields: [String]? = nil,
    ifMatch etag: String? = nil,
    options: RequestOptions = .init()
  ) async throws -> Model {
    var model = model
    model.id = self.resolve(model.id)
    var headers: [String: String] = [:]
    if let etag { headers["If-Match"] = etag }
    let body = try RequestBody.json(
      model.wire,
      settingPaths: Dictionary(uniqueKeysWithValues: clearing.map { ($0.path, .null) }),
      omitting: model.omittedWireDefaults)
    let request = HTTPRequest(
      method: .patch, path: model.id.resourcePath,
      query: SelectedFields.query(selectedFields, required: Self.modelRequiredFields),
      headers: headers, body: body, options: options)
    let wire: GoogleCloudBigQueryV2.Model = try await self.transport.json(
      request, idempotent: etag != nil)
    return Model(wire: wire)
  }

  /// Deletes a model.
  ///
  /// - Parameters:
  ///   - id: the model. A `nil` project means the client's project.
  ///   - options: per-call options.
  /// - Returns: `true` if the model was deleted, `false` if it did not exist. A retried
  ///   request whose first attempt succeeded but whose response was lost also returns `false`.
  @discardableResult
  public func deleteModel(
    _ id: ModelID,
    options: RequestOptions = .init()
  ) async throws -> Bool {
    try await self.transport.deleteOrFalse(
      HTTPRequest(method: .delete, path: self.resolve(id).resourcePath, options: options))
  }

  /// The fields `models.*` always returns when the caller selects fields.
  static let modelRequiredFields = ["modelReference"]
}

extension ModelID {
  /// The REST path of the model, `/bigquery/v2/projects/{p}/datasets/{d}/models/{m}`.
  ///
  /// The ID must be resolved with ``BigQueryClient/resolve(_:)-(ModelID)`` first.
  var resourcePath: String {
    DatasetID(projectID: self.projectID, datasetID: self.datasetID).resourcePath
      + "/models/\(HTTPRequest.encode(segment: self.modelID))"
  }
}
