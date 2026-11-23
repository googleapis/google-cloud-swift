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
import GoogleCloudPubSubV1

// [START pubsub_create_avro_schema]
public func createAvroSchema(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String,
  avscDefinition: String
) async throws -> Schema {
  let schema = try await client.createSchema(
    request: CreateSchemaRequest().with {
      $0.parent = "projects/\(projectID)"
      $0.schemaId = schemaID
      $0.schema = Schema().with { schema in
        schema.type = .avro
        schema.definition = avscDefinition
      }
    }
  )
  print("Created Avro schema: \(schema.name)")
  return schema
}
// [END pubsub_create_avro_schema]

// [START pubsub_create_proto_schema]
public func createProtoSchema(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String,
  protoDefinition: String
) async throws -> Schema {
  let schema = try await client.createSchema(
    request: CreateSchemaRequest().with {
      $0.parent = "projects/\(projectID)"
      $0.schemaId = schemaID
      $0.schema = Schema().with { schema in
        schema.type = .protocolBuffer
        schema.definition = protoDefinition
      }
    }
  )
  print("Created Protobuf schema: \(schema.name)")
  return schema
}
// [END pubsub_create_proto_schema]

// [START pubsub_commit_avro_schema]
public func commitAvroSchema(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String,
  avscDefinition: String
) async throws -> Schema {
  let schemaName = "projects/\(projectID)/schemas/\(schemaID)"
  let schema = try await client.commitSchema(
    request: CommitSchemaRequest().with {
      $0.name = schemaName
      $0.schema = Schema().with { schema in
        schema.name = schemaName
        schema.type = .avro
        schema.definition = avscDefinition
      }
    }
  )
  print("Committed Avro schema \(schema.name) revision \(schema.revisionId)")
  return schema
}
// [END pubsub_commit_avro_schema]

// [START pubsub_commit_proto_schema]
public func commitProtoSchema(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String,
  protoDefinition: String
) async throws -> Schema {
  let schemaName = "projects/\(projectID)/schemas/\(schemaID)"
  let schema = try await client.commitSchema(
    request: CommitSchemaRequest().with {
      $0.name = schemaName
      $0.schema = Schema().with { schema in
        schema.name = schemaName
        schema.type = .protocolBuffer
        schema.definition = protoDefinition
      }
    }
  )
  print("Committed Protobuf schema \(schema.name) revision \(schema.revisionId)")
  return schema
}
// [END pubsub_commit_proto_schema]

// [START pubsub_get_schema]
public func getSchema(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String
) async throws -> Schema {
  let schema = try await client.getSchema(
    request: GetSchemaRequest().with {
      $0.name = "projects/\(projectID)/schemas/\(schemaID)"
      $0.view = .full
    }
  )
  print("Fetched schema: \(schema.name) (\(schema.type))")
  return schema
}
// [END pubsub_get_schema]

// [START pubsub_get_schema_revision]
public func getSchemaRevision(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String,
  revisionID: String
) async throws -> Schema {
  let schema = try await client.getSchema(
    request: GetSchemaRequest().with {
      $0.name = "projects/\(projectID)/schemas/\(schemaID)@\(revisionID)"
      $0.view = .full
    }
  )
  print("Fetched schema revision \(schema.revisionId): \(schema.name)")
  return schema
}
// [END pubsub_get_schema_revision]

// [START pubsub_list_schemas]
public func listSchemas(
  client: any Clients.SchemaServiceProtocol,
  projectID: String
) async throws -> [String] {
  var names: [String] = []
  let items = client.listSchemasByItems(
    request: ListSchemasRequest().with {
      $0.parent = "projects/\(projectID)"
      $0.view = .full
    }
  )
  for try await schema in items {
    print("Schema: \(schema.name)")
    names.append(schema.name)
  }
  return names
}
// [END pubsub_list_schemas]

// [START pubsub_list_schema_revisions]
public func listSchemaRevisions(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String
) async throws -> [String] {
  var revisionIDs: [String] = []
  let items = client.listSchemaRevisionsByItems(
    request: ListSchemaRevisionsRequest().with {
      $0.name = "projects/\(projectID)/schemas/\(schemaID)"
      $0.view = .basic
    }
  )
  for try await revision in items {
    print("Schema revision: \(revision.revisionId)")
    revisionIDs.append(revision.revisionId)
  }
  return revisionIDs
}
// [END pubsub_list_schema_revisions]

// [START pubsub_rollback_schema]
public func rollbackSchema(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String,
  revisionID: String
) async throws -> Schema {
  let schema = try await client.rollbackSchema(
    request: RollbackSchemaRequest().with {
      $0.name = "projects/\(projectID)/schemas/\(schemaID)"
      $0.revisionId = revisionID
    }
  )
  print("Rolled back schema \(schema.name) to revision \(schema.revisionId)")
  return schema
}
// [END pubsub_rollback_schema]

// [START pubsub_delete_schema_revision]
public func deleteSchemaRevision(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String,
  revisionID: String
) async throws -> Schema {
  let schema = try await client.deleteSchemaRevision(
    request: DeleteSchemaRevisionRequest().with {
      $0.name = "projects/\(projectID)/schemas/\(schemaID)@\(revisionID)"
    }
  )
  print("Deleted schema revision \(revisionID) of \(schema.name)")
  return schema
}
// [END pubsub_delete_schema_revision]

// [START pubsub_delete_schema]
public func deleteSchema(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String
) async throws {
  try await client.deleteSchema(
    request: DeleteSchemaRequest().with {
      $0.name = "projects/\(projectID)/schemas/\(schemaID)"
    }
  )
  print("Deleted schema projects/\(projectID)/schemas/\(schemaID)")
}
// [END pubsub_delete_schema]

// [START pubsub_validate_schema]
public func validateSchema(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaType: Schema.Type_,
  definition: String
) async throws -> ValidateSchemaResponse {
  let response = try await client.validateSchema(
    request: ValidateSchemaRequest().with {
      $0.parent = "projects/\(projectID)"
      $0.schema = Schema().with { schema in
        schema.type = schemaType
        schema.definition = definition
      }
    }
  )
  print("Validated schema successfully")
  return response
}
// [END pubsub_validate_schema]

// [START pubsub_validate_message]
public func validateMessage(
  client: any Clients.SchemaServiceProtocol,
  projectID: String,
  schemaID: String,
  payload: Data,
  encoding: Encoding = .json
) async throws -> ValidateMessageResponse {
  let response = try await client.validateMessage(
    request: ValidateMessageRequest().with {
      $0.parent = "projects/\(projectID)"
      $0.schemaSpec = .name("projects/\(projectID)/schemas/\(schemaID)")
      $0.message = payload
      $0.encoding = encoding
    }
  )
  print("Validated message against schema projects/\(projectID)/schemas/\(schemaID)")
  return response
}
// [END pubsub_validate_message]
