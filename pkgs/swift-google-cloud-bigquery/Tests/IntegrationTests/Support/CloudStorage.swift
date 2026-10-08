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
@_spi(GoogleCloudInternal) import GoogleGax

@testable import GoogleCloudBigQuery

/// The few Cloud Storage JSON API calls the integration tests need: buckets for load, extract,
/// and external-table tests.
///
/// This reuses the BigQuery transport against the Cloud Storage endpoint instead of depending on
/// `swift-google-cloud-storage`, whose gRPC dependencies would be built by every `swift test`.
struct CloudStorage {
  static let endpoint = "https://storage.googleapis.com"

  let transport: BigQueryTransport

  init() throws {
    let options = ClientOptions().with { $0.retryPolicy = BigQueryRetryPolicy.defaultPolicy }
    let http = try GoogleGax._HTTPClient(from: options, withDefaultEndpoint: Self.endpoint)
    self.transport = BigQueryTransport(http: GaxHTTPTransport(client: http), clientOptions: options)
  }

  private struct Bucket: Codable {
    var name: String
    var labels: [String: String]?
    var location: String?
  }

  private struct BucketList: Decodable {
    var items: [Bucket]?
    var nextPageToken: String?
  }

  private struct Object: Decodable {
    var name: String
  }

  private struct ObjectList: Decodable {
    var items: [Object]?
    var nextPageToken: String?
  }

  private static func segment(_ value: String) -> String { HTTPRequest.encode(segment: value) }

  /// Creates a bucket in the `US` multi-region.
  func createBucket(_ name: String, projectID: String, labels: [String: String]) async throws {
    let body = try JSONEncoder().encode(Bucket(name: name, labels: labels, location: "US"))
    _ = try await self.transport.send(
      HTTPRequest(
        method: .post, path: "/storage/v1/b",
        query: [URLQueryItem(name: "project", value: projectID)],
        headers: ["content-type": "application/json"], body: body),
      idempotent: false)
  }

  /// Returns the names of the buckets in `projectID` that start with `prefix`.
  func listBuckets(projectID: String, prefix: String) async throws -> [String] {
    var names: [String] = []
    var pageToken: String? = nil
    repeat {
      var query = [
        URLQueryItem(name: "project", value: projectID),
        URLQueryItem(name: "prefix", value: prefix),
      ]
      if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
      let response = try await self.transport.send(
        HTTPRequest(method: .get, path: "/storage/v1/b", query: query), idempotent: true)
      let page = try JSONDecoder().decode(BucketList.self, from: response.body)
      names += (page.items ?? []).map(\.name)
      pageToken = page.nextPageToken
    } while pageToken != nil
    return names
  }

  /// Deletes every object in the bucket, then the bucket.
  func deleteBucket(_ bucket: String) async throws {
    for name in try await self.listObjects(bucket: bucket) {
      try await self.deleteObject(bucket: bucket, name: name)
    }
    _ = try await self.transport.deleteOrFalse(
      HTTPRequest(method: .delete, path: "/storage/v1/b/\(Self.segment(bucket))"))
  }

  /// Uploads `data` as the object `name`.
  func upload(
    bucket: String, name: String, data: Data, contentType: String = "application/octet-stream"
  ) async throws {
    _ = try await self.transport.send(
      HTTPRequest(
        method: .post, path: "/upload/storage/v1/b/\(Self.segment(bucket))/o",
        query: [
          URLQueryItem(name: "uploadType", value: "media"), URLQueryItem(name: "name", value: name),
        ],
        headers: ["content-type": contentType], body: data),
      idempotent: true)
  }

  /// Returns the contents of the object `name`.
  func download(bucket: String, name: String) async throws -> Data {
    try await self.transport.send(
      HTTPRequest(
        method: .get, path: "/storage/v1/b/\(Self.segment(bucket))/o/\(Self.segment(name))",
        query: [URLQueryItem(name: "alt", value: "media")]),
      idempotent: true
    ).body
  }

  /// Returns the names of the objects in the bucket that start with `prefix`.
  func listObjects(bucket: String, prefix: String? = nil) async throws -> [String] {
    var names: [String] = []
    var pageToken: String? = nil
    repeat {
      var query: [URLQueryItem] = []
      if let prefix { query.append(URLQueryItem(name: "prefix", value: prefix)) }
      if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
      let response = try await self.transport.send(
        HTTPRequest(method: .get, path: "/storage/v1/b/\(Self.segment(bucket))/o", query: query),
        idempotent: true)
      let page = try JSONDecoder().decode(ObjectList.self, from: response.body)
      names += (page.items ?? []).map(\.name)
      pageToken = page.nextPageToken
    } while pageToken != nil
    return names
  }

  /// Deletes the object `name`.
  func deleteObject(bucket: String, name: String) async throws {
    _ = try await self.transport.deleteOrFalse(
      HTTPRequest(
        method: .delete, path: "/storage/v1/b/\(Self.segment(bucket))/o/\(Self.segment(name))"))
  }
}
