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
import GoogleApi
import GoogleAuth
import GoogleCloudBiglakeV1
import GoogleCloudBuildV1
import GoogleCloudTestHelpers
import GoogleGax
import Testing

/// Verifies that RPCs using `google.api.HttpBody` as the request body or response message send
/// and receive raw bytes and `Content-Type` headers directly instead of JSON-encoding or
/// JSON-decoding the `HttpBody` wrapper message.
///
/// See https://github.com/googleapis/google-cloud-swift/issues/1155.
@Suite struct HttpBodyTests {
  static func options(_ server: CaptureServer) throws -> ClientOptions {
    let credentials = try Credentials(configuration: .anonymous)
    return ClientOptions().with {
      $0.endpoint = server.endpoint
      $0.credentials = credentials
    }
  }

  /// Verifies an RPC with a `google.api.HttpBody` request field (`body: "body"`) and a standard
  /// JSON protobuf response (`ReceiveTriggerWebhookResponse`).
  @Test func receiveTriggerWebhookSendsRawBody() async throws {
    let rawPayload = Data("raw-webhook-payload".utf8)
    try await CaptureServer.withServer { server in
      let client = try CloudBuildClient(Self.options(server))
      _ = try await client.receiveTriggerWebhook(
        request: .init().with {
          $0.projectId = "my-project"
          $0.trigger = "my-trigger"
          $0.body = GoogleApi.HttpBody().with {
            $0.data = rawPayload
            $0.contentType = "text/plain; charset=utf-8"
          }
        })

      let request = try #require(server.requests.first)
      #expect(request.method == .POST)
      #expect(
        request.uri.hasPrefix("/v1/projects/my-project/triggers/my-trigger:webhook?"))
      #expect(request.body == rawPayload)
      #expect(request.headers.first(name: "content-type") == "text/plain; charset=utf-8")
    }
  }

  /// Verifies an RPC that both sends a `google.api.HttpBody` request field (`body: "http_body"`)
  /// and returns a `google.api.HttpBody` response.
  @Test func createIcebergTableSendsAndReceivesRawBody() async throws {
    let requestPayload = Data("{\"name\":\"orders\"}".utf8)
    let responsePayload = Data("{\"table-uuid\":\"1234\"}".utf8)
    let contentType = "application/vnd.iceberg+json"

    try await CaptureServer.withServer(
      responding: responsePayload,
      contentType: contentType
    ) { server in
      let client = try IcebergCatalogServiceClient(Self.options(server))
      let response = try await client.createIcebergTable(
        request: .init().with {
          $0.parent = "projects/my-project/catalogs/my-catalog/namespaces/my-ns"
          $0.httpBody = GoogleApi.HttpBody().with {
            $0.data = requestPayload
            $0.contentType = contentType
          }
        })

      let request = try #require(server.requests.first)
      #expect(request.method == .POST)
      #expect(
        request.uri.hasPrefix(
          "/iceberg/v1/restcatalog/v1/projects/my-project/catalogs/my-catalog/namespaces/my-ns/tables?"
        ))
      #expect(request.body == requestPayload)
      #expect(request.headers.first(name: "content-type") == contentType)

      #expect(response.data == responsePayload)
      #expect(response.contentType == contentType)
    }
  }

  /// Verifies an RPC with no request body (`GET`) that returns a non-JSON binary
  /// `google.api.HttpBody` response.
  @Test func getIcebergTableReceivesNonJSONRawResponse() async throws {
    let responsePayload = Data("raw-binary-table-metadata".utf8)
    let contentType = "application/octet-stream"

    try await CaptureServer.withServer(
      responding: responsePayload,
      contentType: contentType
    ) { server in
      let client = try IcebergCatalogServiceClient(Self.options(server))
      let response = try await client.getIcebergTable(
        request: .init().with {
          $0.name = "projects/my-project/catalogs/my-catalog/namespaces/my-ns/tables/my-table"
        })

      let request = try #require(server.requests.first)
      #expect(request.method == .GET)
      #expect(response.data == responsePayload)
      #expect(response.contentType == contentType)
    }
  }

  /// Verifies an RPC with a `google.api.HttpBody` request field (`body: "http_body"`) that returns
  /// `google.protobuf.Empty` (`Void`).
  @Test func reportIcebergTableMetricsSendsRawBodyWithEmptyResponse() async throws {
    let rawMetrics = Data("raw-metrics-payload".utf8)
    let contentType = "application/octet-stream"

    try await CaptureServer.withServer { server in
      let client = try IcebergCatalogServiceClient(Self.options(server))
      try await client.reportIcebergTableMetrics(
        request: .init().with {
          $0.name = "projects/my-project/catalogs/my-catalog/namespaces/my-ns/tables/my-table"
          $0.httpBody = GoogleApi.HttpBody().with {
            $0.data = rawMetrics
            $0.contentType = contentType
          }
        })

      let request = try #require(server.requests.first)
      #expect(request.method == .POST)
      #expect(request.body == rawMetrics)
      #expect(request.headers.first(name: "content-type") == contentType)
    }
  }

  /// Verifies an RPC that sends a standard JSON-encoded protobuf request (`body: "*"` with omitted
  /// path fields) and returns a `google.api.HttpBody` response.
  @Test func registerIcebergTableSendsJSONAndReceivesRawBody() async throws {
    let responsePayload = Data("{\"metadata-location\":\"gs://my-bucket/metadata.json\"}".utf8)
    let contentType = "application/vnd.iceberg+json"

    try await CaptureServer.withServer(
      responding: responsePayload,
      contentType: contentType
    ) { server in
      let client = try IcebergCatalogServiceClient(Self.options(server))
      let response = try await client.registerIcebergTable(
        request: .init().with {
          $0.parent = "projects/my-project/catalogs/my-catalog/namespaces/my-ns"
          $0.name = "orders"
          $0.metadataLocation = "gs://my-bucket/metadata.json"
        })

      let request = try #require(server.requests.first)
      #expect(request.method == .POST)
      #expect(request.headers.first(name: "content-type") == "application/json")
      let json = try request.json()
      #expect(json["parent"] == nil, "unexpected 'parent' in \(json)")
      #expect(json["name"] as? String == "orders")
      #expect(json["metadata-location"] as? String == "gs://my-bucket/metadata.json")

      #expect(response.data == responsePayload)
      #expect(response.contentType == contentType)
    }
  }
}
