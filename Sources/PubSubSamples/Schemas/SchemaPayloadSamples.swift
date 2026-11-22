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
import GoogleCloudPubSub
import GoogleCloudPubSubV1

public struct StateProvinceRecord: Codable, Equatable, Sendable {
  public var name: String
  public var postAbbr: String

  public init(name: String, postAbbr: String) {
    self.name = name
    self.postAbbr = postAbbr
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case postAbbr = "post_abbr"
  }
}

// [START pubsub_publish_avro_records]
public func publishAvroRecords(
  topicAdmin: any GoogleCloudPubSubV1.Clients.TopicAdminProtocol,
  publisher: any GoogleCloudPubSub.Clients.PublisherProtocol,
  projectID: String,
  topicID: String,
  records: [StateProvinceRecord]
) async throws -> [String] {
  let topic = try await topicAdmin.getTopic(
    topic: "projects/\(projectID)/topics/\(topicID)"
  )
  let encoding = topic.schemaSettings?.encoding ?? .json
  let encoder = JSONEncoder()
  var messageIDs: [String] = []
  messageIDs.reserveCapacity(records.count)
  for record in records {
    // Cloud Pub/Sub Avro topics configured with JSON encoding validate UTF-8 JSON objects.
    // Callers using Avro BINARY encoding would substitute an Avro binary encoder when .binary.
    let payload: Data
    switch encoding {
    case .binary, .json, .unspecified:
      payload = try encoder.encode(record)
    default:
      payload = try encoder.encode(record)
    }
    let result = try await publisher.publish(Message(data: payload))
    print("Published Avro record message ID: \(result.messageID)")
    messageIDs.append(result.messageID)
  }
  return messageIDs
}
// [END pubsub_publish_avro_records]

// [START pubsub_subscribe_avro_records]
public func subscribeAvroRecords(
  subscriber: any GoogleCloudPubSub.Clients.SubscriberProtocol,
  subscription: String,
  maxMessages: Int = 1
) async throws -> [StateProvinceRecord] {
  let stream = try subscriber.subscribe(subscription: subscription)
  let decoder = JSONDecoder()
  var decodedRecords: [StateProvinceRecord] = []
  for try await received in stream {
    let encoding = received.message.attributes["googclient_schemaencoding"]
    if encoding == "JSON" || encoding == nil {
      let record = try decoder.decode(StateProvinceRecord.self, from: received.message.data)
      print("Received Avro JSON record: \(record.name) (\(record.postAbbr))")
      decodedRecords.append(record)
    } else {
      print("Received Avro binary record (\(received.message.data.count) bytes)")
    }
    received.ack()
    if decodedRecords.count >= maxMessages {
      break
    }
  }
  _ = try await stream.stop()
  return decodedRecords
}
// [END pubsub_subscribe_avro_records]

// [START pubsub_subscribe_avro_records_with_revisions]
public func subscribeAvroRecordsWithRevisions(
  subscriber: any GoogleCloudPubSub.Clients.SubscriberProtocol,
  schemaClient: any GoogleCloudPubSubV1.Clients.SchemaServiceProtocol,
  subscription: String,
  maxMessages: Int = 1
) async throws -> [StateProvinceRecord] {
  let stream = try subscriber.subscribe(subscription: subscription)
  let decoder = JSONDecoder()
  var schemaCache: [String: Schema] = [:]
  var decodedRecords: [StateProvinceRecord] = []
  for try await received in stream {
    let attrs = received.message.attributes
    if let schemaName = attrs["googclient_schemaname"],
      let revisionID = attrs["googclient_schemarevisionid"]
    {
      let revisionName = "\(schemaName)@\(revisionID)"
      if schemaCache[revisionName] == nil {
        let fetched = try await schemaClient.getSchema(
          request: GetSchemaRequest().with {
            $0.name = revisionName
            $0.view = .full
          }
        )
        schemaCache[revisionName] = fetched
      }
    }
    if attrs["googclient_schemaencoding"] != "BINARY" {
      let record = try decoder.decode(StateProvinceRecord.self, from: received.message.data)
      print("Decoded Avro record using schema revision metadata: \(record.name)")
      decodedRecords.append(record)
    }
    received.ack()
    if decodedRecords.count >= maxMessages {
      break
    }
  }
  _ = try await stream.stop()
  return decodedRecords
}
// [END pubsub_subscribe_avro_records_with_revisions]

// [START pubsub_publish_proto_messages]
public func publishProtoMessages(
  topicAdmin: any GoogleCloudPubSubV1.Clients.TopicAdminProtocol,
  publisher: any GoogleCloudPubSub.Clients.PublisherProtocol,
  projectID: String,
  topicID: String,
  records: [StateProvinceRecord]
) async throws -> [String] {
  let topic = try await topicAdmin.getTopic(
    topic: "projects/\(projectID)/topics/\(topicID)"
  )
  let encoding = topic.schemaSettings?.encoding ?? .json
  let encoder = JSONEncoder()
  var messageIDs: [String] = []
  messageIDs.reserveCapacity(records.count)
  for record in records {
    let payload: Data
    switch encoding {
    case .json:
      payload = try encoder.encode(record)
    case .binary:
      // In production, replace with a generated SwiftProtobuf message's serializedData().
      payload = try encoder.encode(record)
    case .unspecified:
      payload = try encoder.encode(record)
    default:
      payload = try encoder.encode(record)
    }
    let result = try await publisher.publish(Message(data: payload))
    print("Published Protobuf-validated message ID: \(result.messageID)")
    messageIDs.append(result.messageID)
  }
  return messageIDs
}
// [END pubsub_publish_proto_messages]

// [START pubsub_subscribe_proto_messages]
public func subscribeProtoMessages(
  subscriber: any GoogleCloudPubSub.Clients.SubscriberProtocol,
  subscription: String,
  maxMessages: Int = 1
) async throws -> [StateProvinceRecord] {
  let stream = try subscriber.subscribe(subscription: subscription)
  let decoder = JSONDecoder()
  var decodedRecords: [StateProvinceRecord] = []
  for try await received in stream {
    let encoding = received.message.attributes["googclient_schemaencoding"]
    if encoding == "JSON" || encoding == nil {
      let record = try decoder.decode(StateProvinceRecord.self, from: received.message.data)
      print("Received Protobuf JSON message: \(record.name)")
      decodedRecords.append(record)
    } else {
      // In production, parse with MyProtoMessage(serializedBytes: received.message.data).
      print("Received Protobuf binary message (\(received.message.data.count) bytes)")
    }
    received.ack()
    if decodedRecords.count >= maxMessages {
      break
    }
  }
  _ = try await stream.stop()
  return decodedRecords
}
// [END pubsub_subscribe_proto_messages]
