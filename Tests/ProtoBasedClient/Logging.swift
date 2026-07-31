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

import GoogleCloudGax
import GoogleCloudLocation
import GoogleCloudSecretManagerV1
import GoogleCloudTestHelpers
import Logging
import InMemoryLogging
import Testing

/// Run tests for the global endpoint.
public enum Logging {
  static public func run(_ logger: Logger) async throws {
    let projectId = try projectId()
    let handler = InMemoryLogHandler()
    var clientLogger = Logger(label: "logging.test", factory: { (String) in handler })
    clientLogger.logLevel = .debug
    let client = try SecretManagerServiceClient(
      ClientOptions().with { $0.logger = clientLogger })

    logger.info("\nTesting listLocations()")
    let _ = try await client.listLocations(
      request: .init().with { $0.name = "projects/\(projectId)" })

    let enter = try #require(
      handler.entries.first(where: { $0.message.description.starts(with: "enter  : ") }),
      "\(handler.entries)")
    checkMetadata(event: enter)
    let success = try #require(
      handler.entries.first(where: { $0.message.description.starts(with: "success: ") }),
      "\(handler.entries)")
    checkMetadata(event: success)

    await #expect(throws: GoogleCloudGax.RequestError.self) {
      _ = try await client.listLocations(
        request: .init().with { $0.name = "" })
    }
    let error = try #require(
      handler.entries.first(where: { $0.message.description.starts(with: "error  : ") }),
      "\(handler.entries)")
    checkMetadata(event: error)
  }

  static func checkMetadata(
    event: InMemoryLogHandler.Entry, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      event.metadata.contains { (key, value) in
        key == "gcp.artifact.id" && value == .string("google-cloud-secretmanager-v1")
      }, "\(event.metadata)", sourceLocation: sourceLocation)
    #expect(
      event.metadata.contains { (key, value) in
        key == "gcp.client.service" && value == .string("secretmanager")
      }, "\(event.metadata)", sourceLocation: sourceLocation)
    #expect(
      event.metadata.contains { (key, value) in
        key == "gcp.experimental.swift.client" && value == .string("SecretManagerService")
      }, "\(event.metadata)", sourceLocation: sourceLocation)
    #expect(
      event.metadata.contains { (key, value) in key == "gcp.experimental.swift.request.id" },
      "\(event.metadata)", sourceLocation: sourceLocation)
    #expect(
      event.metadata.contains { (key, value) in key == "gcp.experimental.swift.method" },
      "\(event.metadata)", sourceLocation: sourceLocation)
  }
}
