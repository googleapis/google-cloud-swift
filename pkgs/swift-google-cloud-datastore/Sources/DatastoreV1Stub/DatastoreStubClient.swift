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
@_spi(GoogleCloudInternal) package import GoogleGax

/// Namespace for generated Datastore v1 stub implementations.
package enum Clients {
  static let clientHeader: GoogleGax._ApiClientHeader =
    .gapic(packageVersion: "0.6.0")
}

/// Package-internal protocol exposing the generated Datastore v1 RPC pipeline to `GoogleCloudDatastore`.
package protocol DatastoreRPCStub: Sendable {
  func lookup(
    request: LookupRequest, options: GoogleGax.RequestOptions
  ) async throws -> LookupResponse

  func runQuery(
    request: RunQueryRequest, options: GoogleGax.RequestOptions
  ) async throws -> RunQueryResponse

  func runAggregationQuery(
    request: RunAggregationQueryRequest, options: GoogleGax.RequestOptions
  ) async throws -> RunAggregationQueryResponse

  func beginTransaction(
    request: BeginTransactionRequest, options: GoogleGax.RequestOptions
  ) async throws -> BeginTransactionResponse

  func commit(
    request: CommitRequest, options: GoogleGax.RequestOptions
  ) async throws -> CommitResponse

  func rollback(
    request: RollbackRequest, options: GoogleGax.RequestOptions
  ) async throws -> RollbackResponse

  func allocateIds(
    request: AllocateIdsRequest, options: GoogleGax.RequestOptions
  ) async throws -> AllocateIdsResponse

  func reserveIds(
    request: ReserveIdsRequest, options: GoogleGax.RequestOptions
  ) async throws -> ReserveIdsResponse
}

extension Clients.DatastoreTransport: DatastoreRPCStub {}
extension Clients.DatastoreRetry: DatastoreRPCStub {}
extension Clients.DatastoreLogging: DatastoreRPCStub {}

/// Factory constructing the HTTP/JSON transport + retry + logging pipeline for `google.datastore.v1`.
package enum DatastoreStubFactory {
  package static func makeStub(
    _ options: GoogleGax.ClientOptions = .init()
  ) throws -> any DatastoreRPCStub {
    var inner: any Clients.DatastoreStub = try Clients.DatastoreTransport(options)
    inner = Clients.DatastoreRetry(inner, options: options)
    if let logger = options.logger {
      inner = Clients.DatastoreLogging(inner, logger: logger)
    }
    guard let rpcStub = inner as? any DatastoreRPCStub else {
      throw GoogleGax.RequestError.unimplemented
    }
    return rpcStub
  }
}

func resolveDatastoreIdempotency(
  isIdempotent: Bool,
  options: GoogleGax.RequestOptions
) -> GoogleGax.RequestOptions {
  var options = options
  options.idempotent = options.idempotent ?? isIdempotent
  return options
}

extension LookupRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveDatastoreIdempotency(isIdempotent: true, options: options)
  }
}

extension RunQueryRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveDatastoreIdempotency(isIdempotent: true, options: options)
  }
}

extension RunAggregationQueryRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveDatastoreIdempotency(isIdempotent: true, options: options)
  }
}

extension ReserveIdsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveDatastoreIdempotency(isIdempotent: true, options: options)
  }
}

extension BeginTransactionRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveDatastoreIdempotency(isIdempotent: false, options: options)
  }
}

extension CommitRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveDatastoreIdempotency(isIdempotent: false, options: options)
  }
}

extension RollbackRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveDatastoreIdempotency(isIdempotent: false, options: options)
  }
}

extension AllocateIdsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveDatastoreIdempotency(isIdempotent: false, options: options)
  }
}
