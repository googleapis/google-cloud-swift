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

import DatastoreV1Stub
import Foundation
import GoogleGax

extension DatastoreClient {
  public func get(_ key: Key, options: ReadOptions? = nil) async throws -> Entity? {
    let results = try await getMulti([key], options: options)
    return results.first ?? nil
  }

  public func getMulti(_ keys: [Key], options: ReadOptions? = nil) async throws -> [Entity?] {
    try await lookupInternal(
      keys: keys,
      wireReadOptions: options?.toWireReadOptions(),
      propertyMask: options?.propertyMask,
      requestOptions: options?.requestOptions
    )
  }

  func lookupInternal(
    keys: [Key],
    wireReadOptions: DatastoreV1Stub.ReadOptions?,
    propertyMask: [String]?,
    requestOptions: GoogleGax.RequestOptions?,
    onFirstResponse: (@Sendable (Data) -> Void)? = nil
  ) async throws -> [Entity?] {
    guard !keys.isEmpty else { return [] }

    // Deduplicate input keys while recording all original indices for each normalized key.
    var uniqueWireKeys: [DatastoreV1Stub.Key] = []
    var normalizedKeyOrder: [Key] = []
    var indicesByKey: [Key: [Int]] = [:]

    for (index, key) in keys.enumerated() {
      let wireKey = key.toProto(
        defaultProjectId: projectId,
        defaultDatabaseId: databaseId,
        defaultNamespaceId: namespaceId
      )
      let normalized = try Key(fromProto: wireKey)
      if indicesByKey[normalized] == nil {
        indicesByKey[normalized] = [index]
        normalizedKeyOrder.append(normalized)
        uniqueWireKeys.append(wireKey)
      } else {
        indicesByKey[normalized]?.append(index)
      }
    }

    var foundByKey: [Key: Entity] = [:]
    var pendingWireKeys = uniqueWireKeys
    var currentReadOptions = wireReadOptions
    var isFirstRound = true
    let wireMask: DatastoreV1Stub.PropertyMask? = propertyMask.map { paths in
      DatastoreV1Stub.PropertyMask().with { $0.paths = paths }
    }
    let effectiveOpts = effectiveRequestOptions(requestOptions)

    while !pendingWireKeys.isEmpty {
      let request = DatastoreV1Stub.LookupRequest().with {
        $0.projectId = projectId
        $0.databaseId = databaseId
        $0.keys = pendingWireKeys
        $0.readOptions = currentReadOptions
        $0.propertyMask = wireMask
      }
      let response = try await stub.lookup(request: request, options: effectiveOpts)
      if isFirstRound {
        isFirstRound = false
        if !response.transaction.isEmpty {
          onFirstResponse?(response.transaction)
          currentReadOptions = DatastoreV1Stub.ReadOptions().with {
            $0.consistencyType = .transaction(response.transaction)
          }
        }
      }
      for entityResult in response.found {
        let decoded = try Entity(fromEntityResult: entityResult)
        let wireKey = decoded.key.toProto(
          defaultProjectId: projectId,
          defaultDatabaseId: databaseId,
          defaultNamespaceId: namespaceId
        )
        let normalized = try Key(fromProto: wireKey)
        foundByKey[normalized] = decoded
      }
      pendingWireKeys = response.deferred
    }

    var orderedResults = [Entity?](repeating: nil, count: keys.count)
    for (normalizedKey, entity) in foundByKey {
      if let indices = indicesByKey[normalizedKey] {
        for idx in indices {
          orderedResults[idx] = entity
        }
      }
    }
    return orderedResults
  }
}
