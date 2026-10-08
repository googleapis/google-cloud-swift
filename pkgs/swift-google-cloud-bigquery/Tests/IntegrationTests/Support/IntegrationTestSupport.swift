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
import GoogleGax
import Testing

@testable import GoogleCloudBigQuery

/// `true` when the live integration tests should run.
func integrationTestsEnabled() -> Bool {
  IntegrationTest.projectID != nil
}

/// Helpers shared by every live integration test.
///
/// Every resource a test creates is named with ``uniqueName(_:)`` and labeled with
/// ``label``. Use ``withTemporaryDataset(_:slice:location:_:)`` and
/// ``withTemporaryBucket(slice:_:)`` so resources are deleted even when the test fails.
enum IntegrationTest {
  /// The project the tests run in, from `GOOGLE_CLOUD_PROJECT`.
  static var projectID: String? {
    ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"].flatMap { $0.isEmpty ? nil : $0 }
  }

  /// The prefix of every dataset the tests create. The janitor only deletes these.
  static let datasetPrefix = "swift_bq_it_"

  /// The prefix of every bucket the tests create. The janitor only deletes these.
  static let bucketPrefix = "swift-bq-it-"

  /// The label set on every dataset and bucket the tests create.
  static let label = (key: "swift-bq-it", value: "true")

  /// Resources older than this are deleted by ``cleanUpStaleResources(_:)``.
  static let staleAge: Duration = .seconds(24 * 60 * 60)

  /// Returns a unique BigQuery-safe name: `swift_bq_it_<yyyymmdd>_<slice>_<hex>`.
  static func uniqueName(_ slice: String) -> String {
    "\(Self.datasetPrefix)\(Self.dateStamp(Date()))_\(slice)_\(Self.randomHex())"
  }

  /// Returns a unique bucket name: `swift-bq-it-<yyyymmdd>-<slice>-<hex>`.
  static func uniqueBucketName(_ slice: String) -> String {
    "\(Self.bucketPrefix)\(Self.dateStamp(Date()))-\(slice)-\(Self.randomHex())"
  }

  /// Creates a client for the test project.
  static func makeClient() throws -> BigQueryClient {
    try BigQueryClient(BigQueryClientOptions().with { $0.projectID = Self.projectID })
  }

  /// Creates a labeled dataset, runs `body`, and deletes the dataset and its contents.
  static func withTemporaryDataset<Result>(
    _ client: BigQueryClient,
    slice: String,
    location: String? = nil,
    _ body: (DatasetID) async throws -> Result
  ) async throws -> Result {
    let id = client.resolve(DatasetID(datasetID: Self.uniqueName(slice)))
    let dataset = GoogleCloudBigQueryV2.Dataset().with {
      $0.datasetReference = id.wire
      $0.labels = [Self.label.key: Self.label.value]
      $0.location = location ?? ""
    }
    let _: GoogleCloudBigQueryV2.Dataset = try await client.transport.json(
      HTTPRequest(
        method: .post, path: "/bigquery/v2/projects/\(id.projectID!)/datasets",
        body: try RequestBody.json(dataset)),
      idempotent: false)
    do {
      let result = try await body(id)
      try await Self.deleteDataset(client, id)
      return result
    } catch {
      try? await Self.deleteDataset(client, id)
      throw error
    }
  }

  /// Creates a labeled Cloud Storage bucket, runs `body`, and deletes the bucket and its
  /// objects.
  static func withTemporaryBucket<Result>(
    slice: String,
    _ body: (String) async throws -> Result
  ) async throws -> Result {
    let storage = try CloudStorage()
    let bucket = Self.uniqueBucketName(slice)
    try await storage.createBucket(
      bucket, projectID: Self.projectID!, labels: [Self.label.key: Self.label.value])
    do {
      let result = try await body(bucket)
      try await storage.deleteBucket(bucket)
      return result
    } catch {
      try? await storage.deleteBucket(bucket)
      throw error
    }
  }

  /// Deletes test datasets and buckets older than ``staleAge``, left behind by crashed runs.
  ///
  /// Only datasets that carry ``label`` and buckets whose name starts with ``bucketPrefix`` are
  /// considered, and only when the name carries a parseable date before yesterday (UTC).
  static func cleanUpStaleResources(_ client: BigQueryClient) async throws {
    let cutoff = Self.dateStamp(Date().addingTimeInterval(-24 * 60 * 60))
    let projectID = client.projectID
    var pageToken: String? = nil
    repeat {
      var query = [
        URLQueryItem(name: "filter", value: "labels.\(Self.label.key):\(Self.label.value)")
      ]
      if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
      let page: GoogleCloudBigQueryV2.DatasetList = try await client.transport.json(
        HTTPRequest(
          method: .get, path: "/bigquery/v2/projects/\(projectID)/datasets", query: query),
        idempotent: true)
      for item in page.datasets {
        let name = item.datasetReference?.datasetId ?? ""
        if Self.isStale(name, prefix: Self.datasetPrefix, cutoff: cutoff) {
          try? await Self.deleteDataset(client, DatasetID(projectID: projectID, datasetID: name))
        }
      }
      pageToken = page.nextPageToken.isEmpty ? nil : page.nextPageToken
    } while pageToken != nil

    let storage = try CloudStorage()
    for bucket in try await storage.listBuckets(projectID: projectID, prefix: Self.bucketPrefix)
    where Self.isStale(bucket, prefix: Self.bucketPrefix, cutoff: cutoff) {
      try? await storage.deleteBucket(bucket)
    }
  }

  static func deleteDataset(_ client: BigQueryClient, _ id: DatasetID) async throws {
    _ = try await client.transport.deleteOrFalse(
      HTTPRequest(
        method: .delete,
        path: "/bigquery/v2/projects/\(id.projectID!)/datasets/\(id.datasetID)",
        query: [URLQueryItem(name: "deleteContents", value: "true")]))
  }

  /// `true` if `name` is `<prefix><yyyymmdd>...` with a date strictly before `cutoff`.
  static func isStale(_ name: String, prefix: String, cutoff: String) -> Bool {
    guard name.hasPrefix(prefix) else { return false }
    let date = name.dropFirst(prefix.count).prefix(8)
    guard date.count == 8, date.allSatisfy(\.isNumber) else { return false }
    return date < cutoff
  }

  static func dateStamp(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)
  }

  static func randomHex() -> String {
    String(UInt32.random(in: .min ... .max), radix: 16)
  }
}
