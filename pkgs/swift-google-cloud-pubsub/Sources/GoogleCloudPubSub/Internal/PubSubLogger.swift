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

import GoogleGax
import GoogleRpc
package import Logging

package enum PubSubRPCMethod: String, Sendable {
  case publish = "google.pubsub.v1.Publisher/Publish"
  case pull = "google.pubsub.v1.Subscriber/Pull"
  case acknowledge = "google.pubsub.v1.Subscriber/Acknowledge"
  case modifyAckDeadline = "google.pubsub.v1.Subscriber/ModifyAckDeadline"
  case streamingPull = "google.pubsub.v1.Subscriber/StreamingPull"
}

package struct PubSubLogger: Sendable {
  package static let artifactID = "google-cloud-pubsub"
  package static let clientService = "pubsub"
  package static let clientRepo = "googleapis/google-cloud-swift"

  private let logger: Logging.Logger?

  package init(_ logger: Logging.Logger?) {
    self.logger = logger
  }

  package func logRPCDebug(
    _ message: @autoclosure () -> String,
    method: PubSubRPCMethod,
    resource: String,
    extraMetadata: Logging.Logger.Metadata = [:]
  ) {
    guard let logger else { return }
    var metadata = Self.baseMetadata(method: method, resource: resource)
    for (k, v) in extraMetadata {
      metadata[k] = v
    }
    logger.debug("\(message())", metadata: metadata)
  }

  package func logTerminalError(
    _ error: any Error,
    method: PubSubRPCMethod,
    resource: String,
    operation: String
  ) {
    guard let logger else { return }
    var metadata = Self.baseMetadata(method: method, resource: resource)
    metadata["error.type"] = "\(String(describing: type(of: error)))"
    metadata["error.message"] = "\(error)"
    if let requestError = error as? GoogleGax.RequestError,
      case .service(let serviceError) = requestError
    {
      metadata["rpc.grpc.status_code"] =
        "\(serviceError.code.stringValue ?? "\(serviceError.code)")"
    }
    logger.error(
      "Pub/Sub operation \(operation) failed",
      metadata: metadata
    )
  }

  package static func baseMetadata(
    method: PubSubRPCMethod,
    resource: String
  ) -> Logging.Logger.Metadata {
    [
      "gcp.artifact.id": .string(Self.artifactID),
      "gcp.client.service": .string(Self.clientService),
      "gcp.client.version": .string(PackageVersion.version),
      "gcp.client.repo": .string(Self.clientRepo),
      "gcp.resource.destination.id": .string("//pubsub.googleapis.com/\(resource)"),
      "rpc.system": "grpc",
      "rpc.method": .string(method.rawValue),
    ]
  }
}
