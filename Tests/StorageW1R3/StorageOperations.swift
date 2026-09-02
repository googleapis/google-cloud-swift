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
import NIOCore
import GoogleCloudAuth
import GoogleCloudGax
import GoogleCloudStorage

enum StorageOperations {
  /// Uploads data to Google Cloud Storage.
  static func upload(
    client: StorageClient,
    controlClient: StorageControlClient,
    bucketName: String,
    objectName: String,
    buffer: NIOCore.ByteBuffer,
    isResumable: Bool
  ) async throws -> GoogleCloudStorage.Object {
    let options = UploadOptions().with {
      $0.preconditions = StoragePreconditions().with {
        $0.ifGenerationMatch = 0
      }
      // If resumable, chunk size is set to 32MiB; if simple, threshold handles it
      if isResumable {
        $0.chunkSize = 32 * 1024 * 1024
        $0.resumableUploadThreshold = buffer.readableBytes
      } else {
        $0.resumableUploadThreshold = buffer.readableBytes + 256 * 1024
      }
    }

    do {
      return try await client.upload(
        BytesSource(buffer: .init(buffer)), to: bucketName, as: objectName, options: options)
    } catch {
      // If precondition failed (412), check if object already exists
      if let reqError = error as? RequestError,
        case .http(let details) = reqError,
        details.http_status_code == 412
      {
        logToStderr("Precondition failed for \(objectName), fetching object details")
        let getReq = GetObjectRequest().with {
          $0.bucket = "projects/_/buckets/\(bucketName)"
          $0.object = objectName
        }
        let object = try await controlClient.getObject(request: getReq, options: .init())
        return object
      }
      throw error
    }
  }

  /// Downloads (reads) an object from Cloud Storage, returning total bytes transferred.
  static func download(
    client: StorageClient, object: GoogleCloudStorage.Object
  ) async -> (transferSize: Int, error: (any Error)?) {
    var options = ReadObjectOptions()
    if object.generation > 0 {
      options.generation = UInt64(object.generation)
    }

    let readTask = client.readObject(from: object.bucket, object: object.name, options: options)
    var transferSize = 0
    do {
      for try await chunk in readTask.body {
        transferSize += chunk.count
      }
      return (transferSize, nil)
    } catch {
      return (transferSize, error)
    }
  }

  /// Deletes a batch of objects in parallel using StorageControlClient.
  static func batchDelete(
    client: StorageControlClient,
    batch: [GoogleCloudStorage.Object]
  ) async throws {
    guard !batch.isEmpty else { return }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for object in batch {
        group.addTask {
          let deleteReq = DeleteObjectRequest().with {
            $0.bucket = object.bucket
            $0.object = object.name
            $0.generation = object.generation
          }
          do {
            try await client.deleteObject(
              request: deleteReq,
              options: .init().with {
                $0.idempotency = true
                $0.retryPolicy = GoogleCloudGax.BaseRetryPolicy().withTimeLimit(.seconds(30))
                $0.attemptTimeout = .seconds(10)
              })
          } catch {
            // Ignore 404 / NOT_FOUND as it may be due to retry
            if let reqError = error as? RequestError {
              if case .http(let details) = reqError, details.http_status_code == 404 {
                return
              }
              if case .service(let details) = reqError, details.code == .notFound {
                return
              }
            }
            throw error
          }
        }
      }
      try await group.waitForAll()
    }
  }
}
