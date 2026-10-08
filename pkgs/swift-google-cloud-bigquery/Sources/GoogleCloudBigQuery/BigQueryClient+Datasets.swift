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
  /// Creates a dataset.
  ///
  /// The request is not retried: a retry after a lost response would fail with HTTP 409.
  ///
  /// - Parameters:
  ///   - dataset: the dataset to create. A `nil` project in its ID means the client's project,
  ///     which also fills authorized views and routines in ``Dataset/access`` that have none.
  ///   - accessPolicyVersion: the access policy version (1, 2, or 3) of ``Dataset/access``.
  ///     Conditional access entries require version 3.
  ///   - selectedFields: the dataset fields to return, for example `["labels"]`. The ID is
  ///     always returned.
  ///   - options: per-call options.
  /// - Returns: the created dataset, as returned by the service.
  public func createDataset(
    _ dataset: Dataset,
    accessPolicyVersion: Int32? = nil,
    selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Dataset {
    let dataset = dataset.resolved(by: self)
    var query = SelectedFields.query(selectedFields, required: Self.datasetRequiredFields)
    if let accessPolicyVersion {
      query.append(URLQueryItem(name: "accessPolicyVersion", value: String(accessPolicyVersion)))
    }
    let request = HTTPRequest(
      method: .post,
      path: "/bigquery/v2/projects/\(HTTPRequest.encode(segment: dataset.id.projectID!))/datasets",
      query: query,
      body: try RequestBody.json(dataset.wire, omitting: dataset.omittedWireDefaults),
      options: options)
    let wire: GoogleCloudBigQueryV2.Dataset = try await self.transport.json(
      request, idempotent: false)
    return Dataset(wire: wire)
  }

  /// Returns a dataset, or `nil` if it does not exist.
  ///
  /// - Parameters:
  ///   - id: the dataset. A `nil` project means the client's project.
  ///   - view: which parts of the dataset to return. The service default is ``DatasetView/full``.
  ///   - accessPolicyVersion: the access policy version (1, 2, or 3) to return. Conditional
  ///     access entries are returned only for version 3.
  ///   - selectedFields: the dataset fields to return, for example `["labels", "creationTime"]`.
  ///     The ID is always returned.
  ///   - options: per-call options.
  public func getDataset(
    _ id: DatasetID,
    view: DatasetView? = nil,
    accessPolicyVersion: Int32? = nil,
    selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Dataset? {
    var query = SelectedFields.query(selectedFields, required: Self.datasetRequiredFields)
    if let accessPolicyVersion {
      query.append(URLQueryItem(name: "accessPolicyVersion", value: String(accessPolicyVersion)))
    }
    if let view {
      query.append(URLQueryItem(name: "datasetView", value: view.rawValue))
    }
    let request = HTTPRequest(
      method: .get, path: self.resolve(id).resourcePath, query: query, options: options)
    return try await self.transport.jsonOrNil(request, as: GoogleCloudBigQueryV2.Dataset.self)
      .map(Dataset.init(wire:))
  }

  /// Lists the datasets in a project.
  ///
  /// The datasets are partial; see ``Dataset``. Use ``getDataset(_:view:accessPolicyVersion:selectedFields:options:)``
  /// for the full resource.
  ///
  /// - Parameters:
  ///   - projectID: the project, or `nil` for the client's project.
  ///   - all: whether to include hidden datasets (names starting with `_`).
  ///   - filter: a label filter, for example `labels.env:prod` or `labels.env`.
  ///   - pageSize: the maximum number of datasets per page, or `nil` for the service default.
  ///   - pageToken: the page to start from, from ``Page/nextPageToken``.
  ///   - options: per-call options, applied to every page request.
  public func listDatasets(
    projectID: String? = nil,
    all: Bool = false,
    filter: String? = nil,
    pageSize: Int? = nil,
    pageToken: String? = nil,
    options: RequestOptions = .init()
  ) -> PagedSequence<Dataset> {
    let path = "/bigquery/v2/projects/\(HTTPRequest.encode(segment: projectID ?? self.projectID))/datasets"
    var query: [URLQueryItem] = []
    if all { query.append(URLQueryItem(name: "all", value: "true")) }
    if let filter { query.append(URLQueryItem(name: "filter", value: filter)) }
    if let pageSize { query.append(URLQueryItem(name: "maxResults", value: String(pageSize))) }
    return PagedSequence { [transport, query] token in
      var pageQuery = query
      if let token = token ?? pageToken {
        pageQuery.append(URLQueryItem(name: "pageToken", value: token))
      }
      let list: GoogleCloudBigQueryV2.DatasetList = try await transport.json(
        HTTPRequest(method: .get, path: path, query: pageQuery, options: options),
        idempotent: true)
      return Page(
        items: list.datasets.map(Dataset.init(wire:)), nextPageToken: list.nextPageToken.nonEmpty)
    }
  }

  /// Updates a dataset with the non-`nil` properties of `dataset` (HTTP PATCH).
  ///
  /// `nil` properties are left unchanged, ``Dataset/labels`` are merged into the existing
  /// labels, and ``Dataset/access`` replaces the existing list. To remove a value, name it in
  /// `clearing`; clearing takes precedence over a value set in `dataset`.
  ///
  /// ```swift
  /// var change = Dataset(id: id, description: "Nightly exports")
  /// change.labels = ["env": "prod"]
  /// try await client.updateDataset(change, clearing: [.label("owner")])
  /// ```
  ///
  /// The request is retried only when `etag` is given, because a retried PATCH could
  /// otherwise overwrite a concurrent change.
  ///
  /// - Parameters:
  ///   - dataset: the dataset ID and the properties to change.
  ///   - clearing: the properties to remove.
  ///   - updateMode: which parts of the dataset to change. The service default changes both
  ///     metadata and the access list.
  ///   - accessPolicyVersion: the access policy version (1, 2, or 3) of ``Dataset/access``.
  ///   - selectedFields: the dataset fields to return. The ID is always returned.
  ///   - etag: update only if the dataset's current ``Dataset/etag`` matches (`If-Match`).
  ///     A mismatch fails with HTTP 412.
  ///   - options: per-call options.
  /// - Returns: the updated dataset.
  public func updateDataset(
    _ dataset: Dataset,
    clearing: Set<Dataset.Field> = [],
    updateMode: DatasetUpdateMode? = nil,
    accessPolicyVersion: Int32? = nil,
    selectedFields: [String]? = nil,
    ifMatch etag: String? = nil,
    options: RequestOptions = .init()
  ) async throws -> Dataset {
    let dataset = dataset.resolved(by: self)
    var query = SelectedFields.query(selectedFields, required: Self.datasetRequiredFields)
    if let accessPolicyVersion {
      query.append(URLQueryItem(name: "accessPolicyVersion", value: String(accessPolicyVersion)))
    }
    if let updateMode {
      query.append(URLQueryItem(name: "updateMode", value: updateMode.rawValue))
    }
    var headers: [String: String] = [:]
    if let etag { headers["If-Match"] = etag }
    let body = try RequestBody.json(
      dataset.wire,
      setting: Dictionary(uniqueKeysWithValues: clearing.map { ($0.path, .null) }),
      omitting: dataset.omittedWireDefaults)
    let request = HTTPRequest(
      method: .patch, path: dataset.id.resourcePath, query: query, headers: headers, body: body,
      options: options)
    let wire: GoogleCloudBigQueryV2.Dataset = try await self.transport.json(
      request, idempotent: etag != nil)
    return Dataset(wire: wire)
  }

  /// Deletes a dataset.
  ///
  /// - Parameters:
  ///   - id: the dataset. A `nil` project means the client's project.
  ///   - deleteContents: whether to also delete the dataset's tables, views, routines, and
  ///     models. When `false`, deleting a non-empty dataset fails.
  ///   - options: per-call options.
  /// - Returns: `true` if the dataset was deleted, `false` if it did not exist. A retried
  ///   request whose first attempt succeeded but whose response was lost also returns `false`.
  @discardableResult
  public func deleteDataset(
    _ id: DatasetID,
    deleteContents: Bool = false,
    options: RequestOptions = .init()
  ) async throws -> Bool {
    var query: [URLQueryItem] = []
    if deleteContents { query.append(URLQueryItem(name: "deleteContents", value: "true")) }
    return try await self.transport.deleteOrFalse(
      HTTPRequest(
        method: .delete, path: self.resolve(id).resourcePath, query: query, options: options))
  }

  /// The fields `datasets.*` always returns when the caller selects fields.
  static let datasetRequiredFields = ["datasetReference"]
}

extension DatasetID {
  /// The REST path of the dataset, `/bigquery/v2/projects/{p}/datasets/{d}`.
  ///
  /// The ID must be resolved with ``BigQueryClient/resolve(_:)-(DatasetID)`` first.
  var resourcePath: String {
    "/bigquery/v2/projects/\(HTTPRequest.encode(segment: self.projectID ?? ""))"
      + "/datasets/\(HTTPRequest.encode(segment: self.datasetID))"
  }
}

/// Builds the `fields` query parameter that selects the fields of a response.
enum SelectedFields {
  /// Returns `fields=<required>,<fields>` with duplicates removed, or no parameter when
  /// `fields` is `nil`.
  static func query(_ fields: [String]?, required: [String]) -> [URLQueryItem] {
    guard let fields else { return [] }
    var seen = Set<String>()
    let all = (required + fields).filter { seen.insert($0).inserted }
    return [URLQueryItem(name: "fields", value: all.joined(separator: ","))]
  }
}
