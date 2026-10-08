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
  /// Creates a routine: a user-defined function, table function, or stored procedure.
  ///
  /// The request is not retried: a retry after a lost response would fail with HTTP 409.
  ///
  /// - Parameters:
  ///   - routine: the routine to create. A `nil` project in its ID means the client's project.
  ///   - selectedFields: the routine fields to return, for example `["etag"]`. The ID is always
  ///     returned.
  ///   - options: per-call options.
  /// - Returns: the created routine, as returned by the service.
  @discardableResult
  public func createRoutine(
    _ routine: Routine,
    selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Routine {
    var routine = routine
    routine.id = self.resolve(routine.id)
    let request = HTTPRequest(
      method: .post,
      path: DatasetID(projectID: routine.id.projectID, datasetID: routine.id.datasetID)
        .resourcePath + "/routines",
      query: SelectedFields.query(selectedFields, required: Self.routineRequiredFields),
      body: try RequestBody.json(routine.wire, omitting: routine.omittedWireDefaults),
      options: options)
    let wire: GoogleCloudBigQueryV2.Routine = try await self.transport.json(
      request, idempotent: false)
    return Routine(wire: wire)
  }

  /// Returns a routine, or `nil` if it does not exist.
  ///
  /// - Parameters:
  ///   - id: the routine. A `nil` project means the client's project.
  ///   - selectedFields: the routine fields to return, for example `["definitionBody"]`. The ID
  ///     is always returned.
  ///   - options: per-call options.
  public func getRoutine(
    _ id: RoutineID,
    selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Routine? {
    let request = HTTPRequest(
      method: .get, path: self.resolve(id).resourcePath,
      query: SelectedFields.query(selectedFields, required: Self.routineRequiredFields),
      options: options)
    return try await self.transport.jsonOrNil(request, as: GoogleCloudBigQueryV2.Routine.self)
      .map(Routine.init(wire:))
  }

  /// Lists the routines in a dataset.
  ///
  /// The routines are partial: the service omits ``Routine/body``, ``Routine/arguments``, and
  /// other definition fields. Use ``getRoutine(_:selectedFields:options:)`` for the full
  /// resource.
  ///
  /// - Parameters:
  ///   - dataset: the dataset. A `nil` project means the client's project.
  ///   - pageSize: the maximum number of routines per page, or `nil` for the service default.
  ///   - pageToken: the page to start from, from ``Page/nextPageToken``.
  ///   - options: per-call options, applied to every page request.
  public func listRoutines(
    in dataset: DatasetID,
    pageSize: Int? = nil,
    pageToken: String? = nil,
    options: RequestOptions = .init()
  ) -> PagedSequence<Routine> {
    let path = self.resolve(dataset).resourcePath + "/routines"
    return PagedSequence { [transport] token in
      let list: ListRoutinesResponse = try await transport.json(
        HTTPRequest(
          method: .get, path: path, query: ResourcePaging.query(pageSize, token ?? pageToken),
          options: options),
        idempotent: true)
      return Page(
        items: list.routines.map(Routine.init(wire:)), nextPageToken: list.nextPageToken.nonEmpty)
    }
  }

  /// Replaces a routine (HTTP PUT).
  ///
  /// Unlike the other updates, this is a full replacement: properties that are `nil` in
  /// `routine` are removed. Start from the routine returned by
  /// ``getRoutine(_:selectedFields:options:)`` and change what you need. Routine settings
  /// that ``Routine`` does not model (for example `securityMode`, `strictMode`, Spark or
  /// Python options) are not sent either, so the update resets them.
  ///
  /// The request is retried only when `etag` is given, because a retried PUT could otherwise
  /// overwrite a concurrent change.
  ///
  /// - Parameters:
  ///   - routine: the complete new routine.
  ///   - selectedFields: the routine fields to return. The ID is always returned.
  ///   - etag: update only if the routine's current ``Routine/etag`` matches (`If-Match`).
  ///     A mismatch fails with HTTP 412.
  ///   - options: per-call options.
  /// - Returns: the updated routine.
  public func updateRoutine(
    _ routine: Routine,
    selectedFields: [String]? = nil,
    ifMatch etag: String? = nil,
    options: RequestOptions = .init()
  ) async throws -> Routine {
    var routine = routine
    routine.id = self.resolve(routine.id)
    var headers: [String: String] = [:]
    if let etag { headers["If-Match"] = etag }
    let request = HTTPRequest(
      method: .put, path: routine.id.resourcePath,
      query: SelectedFields.query(selectedFields, required: Self.routineRequiredFields),
      headers: headers,
      body: try RequestBody.json(routine.wire, omitting: routine.omittedWireDefaults),
      options: options)
    let wire: GoogleCloudBigQueryV2.Routine = try await self.transport.json(
      request, idempotent: etag != nil)
    return Routine(wire: wire)
  }

  /// Deletes a routine.
  ///
  /// - Parameters:
  ///   - id: the routine. A `nil` project means the client's project.
  ///   - options: per-call options.
  /// - Returns: `true` if the routine was deleted, `false` if it did not exist. A retried
  ///   request whose first attempt succeeded but whose response was lost also returns `false`.
  @discardableResult
  public func deleteRoutine(
    _ id: RoutineID,
    options: RequestOptions = .init()
  ) async throws -> Bool {
    try await self.transport.deleteOrFalse(
      HTTPRequest(method: .delete, path: self.resolve(id).resourcePath, options: options))
  }

  /// The fields `routines.*` always returns when the caller selects fields.
  static let routineRequiredFields = ["routineReference"]
}

extension RoutineID {
  /// The REST path of the routine, `/bigquery/v2/projects/{p}/datasets/{d}/routines/{r}`.
  ///
  /// The ID must be resolved with ``BigQueryClient/resolve(_:)-(RoutineID)`` first.
  var resourcePath: String {
    DatasetID(projectID: self.projectID, datasetID: self.datasetID).resourcePath
      + "/routines/\(HTTPRequest.encode(segment: self.routineID))"
  }
}

/// Builds the paging query parameters of a list request.
enum ResourcePaging {
  /// Returns `maxResults` and `pageToken` parameters for the non-`nil` arguments.
  static func query(_ pageSize: Int?, _ pageToken: String?) -> [URLQueryItem] {
    var query: [URLQueryItem] = []
    if let pageSize { query.append(URLQueryItem(name: "maxResults", value: String(pageSize))) }
    if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
    return query
  }
}
