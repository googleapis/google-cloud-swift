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
import GoogleCloudStorage
import GoogleCloudGax

fileprivate let integrationTestMark = "integration-test"
fileprivate let hour = 3600
fileprivate let maxStaleness = 48 * hour

/// Cleans up any stale buckets in the given project.
public func cleanupStaleTestBuckets(client: StorageControlClient, projectId: String) async {
  var bucketNames: [String] = []
  var requesterNames: [String] = []
  do {
    let deadline = Int(Date().timeIntervalSince1970) - maxStaleness
    let buckets = try client.listBuckets(
      byItem: .init().with { $0.parent = "projects/\(projectId)" }, options: .init())
    for try await b in buckets {
      guard let v = b.labels[integrationTestMark], v == "true" else {
        continue
      }
      guard let created = b.createTime, created.seconds < deadline else {
        continue
      }
      bucketNames.append(b.name)
      if let v = b.billing?.requesterPays, v {
        requesterNames.append(b.name)
      }
    }
  } catch {
    print("ERROR listing buckets for cleanup: \(error)")
  }
  await clearRequesterFlags(client: client, bucketNames: requesterNames)
  await sweepTestBuckets(client: client, bucketNames: bucketNames)
}

/// Cleans up the provided list of test buckets.
///
/// This is called immediately after running an integration test.
public func cleanupTestBuckets(client: StorageControlClient, bucketNames: [String]) async {
  // Many of the buckets created in tests are created as part of a sample. We don't want to show
  // the labels we use for cleanup, as that complicates the example. So the first thing we do is
  // add all the labels that mark the bucket as part of an integration test. We also  reset any
  // attributes that make it hard to delete the bucket.
  await markTestBuckets(client: client, bucketNames: bucketNames)
  // After this we clear the contents and delete the bucket. Rarely this fails either some failed
  // request, or the contents have some retention period. In that case, the bucket will be deleted
  // in a few days, as the integration tests call `cleanupStaleTestBuckets()`.
  await sweepTestBuckets(client: client, bucketNames: bucketNames)
}

/// Marks a number of test buckets for garbage collection.
///
/// When testing the samples, we create any number of buckets. This function marks the buckets for
/// garbage collection. Normally `sweepTestBuckets` step will attempt to delete the buckets too.
func markTestBuckets(client: StorageControlClient, bucketNames: [String]) async {
  for name in bucketNames {
    do {
      let bucket = Bucket().with {
        $0.name = name
        $0.labels = [integrationTestMark: "true"]
        $0.billing = .init().with { $0.requesterPays = false }
      }
      let options = RequestOptions().with {
        $0.idempotency = true
      }
      let _ = try await client.updateBucket(
        request: .init().with {
          $0.bucket = bucket
          $0.updateMask = .init(paths: ["labels", "billing.requester_pays"])
        }, options: options)
    } catch {
      print("ERROR marking bucket \(name): \(error)")
    }
  }
}

/// Resets the requesterPays flag so we can easily delete the bucket.
///
/// On buckets with `requesterPays == false` we need to do a number of
/// When testing the samples, we create any number of buckets. This function marks the buckets for
/// garbage collection. Normally `sweepTestBuckets` step will attempt to delete the buckets too.
func clearRequesterFlags(client: StorageControlClient, bucketNames: [String]) async {
  for name in bucketNames {
    do {
      let bucket = Bucket().with {
        $0.name = name
        $0.billing = .init().with { $0.requesterPays = false }
      }
      let options = RequestOptions().with {
        $0.idempotency = true
      }
      let _ = try await client.updateBucket(
        request: .init().with {
          $0.bucket = bucket
          $0.updateMask = .init(paths: ["billing.requester_pays"])
        }, options: options)
    } catch {
      print("ERROR clearing requester pays bucket \(name): \(error)")
    }
  }
}

/// Deletes a number of test bucket and their contents.
///
/// When testing the samples, we create any number of buckets. This function deletes buckets based
/// on their id.
func sweepTestBuckets(client: StorageControlClient, bucketNames: [String]) async {
  for name in bucketNames {
    do {
      let bucket: Bucket
      do {
        bucket = try await client.getBucket(
          request: .init().with { $0.name = name }, options: .init())
      } catch {
        print("ERROR getting bucket properties for \(name): \(error)")
        continue
      }

      let objects = try client.listObjects(
        byItem: .init().with { $0.parent = bucket.name }, options: .init())
      for try await o in objects {
        try await client.deleteObject(
          request: .init().with {
            $0.bucket = o.bucket
            $0.object = o.name
            $0.generation = o.generation
          }, options: .init().with { $0.idempotency = true })
      }

      let caches = try client.listAnywhereCaches(
        byItem: .init().with { $0.parent = bucket.name }, options: .init())
      for try await c in caches {
        let _ = try await client.disableAnywhereCache(
          request: .init().with { $0.name = c.name },
          options: .init().with { $0.idempotency = true })
      }

      guard let enabled = bucket.hierarchicalNamespace?.enabled, enabled else {
        // Only try to delete folders if the bucket can have folders.
        continue
      }

      let folders = try client.listManagedFolders(
        byItem: .init().with { $0.parent = bucket.name }, options: .init())
      for try await f in folders {
        try await client.deleteFolder(
          request: .init().with { $0.name = f.name },
          options: .init().with { $0.idempotency = true })
      }
    } catch {
      print("ERROR sweeping bucket \(name): \(error)")
    }
  }
}
