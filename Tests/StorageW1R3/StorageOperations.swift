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
import GoogleAuth
import GoogleGax
import GoogleCloudStorage

enum StorageOperations {
  /// Uploads data to Google Cloud Storage.
  static func upload(
    client: StorageClient,
    controlClient: StorageControlClient,
    bucketName: String,
    objectName: String,
    buffer: ByteChunk,
    isResumable: Bool,
    crc32cEnabled: Bool
  ) async throws -> GoogleCloudStorage.Object {
    let options = WriteObjectOptions().with {
      $0.preconditions = StoragePreconditions().with {
        $0.ifGenerationMatch = 0
      }
      $0.checksums = crc32cEnabled ? .default : .none
      // If resumable, chunk size is set to 32MiB; if simple, threshold handles it
      if isResumable {
        $0.chunkSize = 32 * 1024 * 1024
        $0.resumableUploadThreshold = buffer.count
      } else {
        $0.resumableUploadThreshold = buffer.count + 256 * 1024
      }
    }

    do {
      return try await client.writeObject(
        BytesSource(buffer: buffer), to: bucketName, as: objectName, options: options)
    } catch let reqError as RequestError where reqError.isFailedPrecondition {
      logToStderr("Precondition failed for \(objectName), fetching object details")
      let getReq = GetObjectRequest().with {
        $0.bucket = "projects/_/buckets/\(bucketName)"
        $0.object = objectName
      }
      let object = try await controlClient.getObject(request: getReq, options: .init())
      return object
    } catch {
      throw error
    }
  }

  /// Downloads (reads) an object from Cloud Storage, returning total bytes transferred.
  static func download(
    client: StorageClient, object: GoogleCloudStorage.Object, crc32cEnabled: Bool
  ) async -> (transferSize: Int, error: (any Error)?) {
    let options = ReadObjectOptions().with {
      $0.generation = if object.generation > 0 { object.generation } else { nil }
      $0.checksums = crc32cEnabled ? .default : .none
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
                $0.retryPolicy = StorageBaseRetryPolicy.unbounded()
                  .withTimeLimit(.seconds(30))
                  .countedAndLogged(
                    counter: GlobalCounters.retryPolicy,
                    methodName: "deleteObject"
                  )
                $0.attemptTimeout = .seconds(10)
              })
          } catch let reqError as RequestError where reqError.isNotFound {
            // TODO(https://github.com/googleapis/google-cloud-swift/issues/833)
            // These are expected as the retry loop may try to delete the same thing twice, and
            // the service returns an error the second time. Once #833 is implemented the server
            // should return success the second time.
          } catch {
            throw error
          }
        }
      }
      try await group.waitForAll()
    }
  }
}

extension RequestError {
  var isNotFound: Bool {
    if case .service(let details) = self, details.code == .notFound {
      return true
    }
    return false
  }

  var isFailedPrecondition: Bool {
    if case .service(let details) = self, details.code == .failedPrecondition {
      return true
    }
    return false
  }
}
