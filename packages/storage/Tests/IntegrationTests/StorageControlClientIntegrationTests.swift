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
import GoogleCloudAuth
import GoogleCloudGax
@testable import GoogleCloudStorage
import GoogleCloudWkt
import GoogleIAMV1
import Testing

#if IntegrationTests

  @Suite(
    .enabled(
      if: ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil))
  struct StorageControlClientIntegrationTests: Sendable {
    private var projectId: String {
      ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]!
    }

    private var bucketName: String {
      ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"]
        ?? "\(projectId)-test-bucket"
    }

    private var bucketResource: String {
      "projects/_/buckets/\(bucketName)"
    }

    @Test func testListAndDeleteObjects() async throws {
      let uniquePrefix = "test-ctrl-delete-\(UUID().uuidString)"
      let file1 = "\(uniquePrefix)/obj1.txt"
      let file2 = "\(uniquePrefix)/obj2.txt"
      let data = Data("Delete test object".utf8)

      let storageClient = try StorageClient()
      let controlClient = try StorageControlClient()

      // Seed objects for deletion test
      _ = try await storageClient.upload(data, to: bucketName, as: file1).value
      _ = try await storageClient.upload(data, to: bucketName, as: file2).value

      do {
        // List objects with prefix via streaming AsyncSequence
        let sequence = try controlClient.listObjects(
          byItem: ListObjectsRequest().with {
            $0.parent = bucketResource
            $0.prefix = uniquePrefix
          },
          options: .init()
        )

        var objectNames = [String]()
        for try await object in sequence {
          objectNames.append(object.name)
        }
        #expect(objectNames.count == 2)
        #expect(objectNames.contains(file1))
        #expect(objectNames.contains(file2))

        // Delete each discovered object
        for name in objectNames {
          let deleteRequest = DeleteObjectRequest().with {
            $0.bucket = bucketResource
            $0.object = name
          }
          try await controlClient.deleteObject(request: deleteRequest, options: .init())
        }

        // Verify that prefix is now empty
        let verifyRequest = ListObjectsRequest().with {
          $0.parent = bucketResource
          $0.prefix = uniquePrefix
        }
        let finalListing = try await controlClient.listObjects(
          request: verifyRequest, options: .init())
        #expect(
          finalListing.objects.isEmpty, "Expected prefix to be empty after deleting all objects")
      } catch {
        // Cleanup remaining objects on failure
        for file in [file1, file2] {
          _ = try? await controlClient.deleteObject(
            request: DeleteObjectRequest().with {
              $0.bucket = bucketResource
              $0.object = file
            },
            options: .init()
          )
        }
        throw error
      }
    }

    @Test func testListObjectsUnaryAndPagination() async throws {
      let uniquePrefix = "test-ctrl-list-\(UUID().uuidString)"
      let file1 = "\(uniquePrefix)/item1.txt"
      let file2 = "\(uniquePrefix)/item2.txt"
      let file3 = "\(uniquePrefix)/sub/item3.txt"
      let data = Data("Hello gRPC Object Listing and Pagination!".utf8)

      let storageClient = try StorageClient()
      let controlClient = try StorageControlClient()

      // Seed test objects using data-plane veneer
      _ = try await storageClient.upload(data, to: bucketName, as: file1).value
      _ = try await storageClient.upload(data, to: bucketName, as: file2).value
      _ = try await storageClient.upload(data, to: bucketName, as: file3).value

      do {
        // Unary list with prefix and pageSize
        let listRequest = ListObjectsRequest().with {
          $0.parent = bucketResource
          $0.prefix = uniquePrefix
          $0.pageSize = 2
        }
        let firstPage = try await controlClient.listObjects(request: listRequest, options: .init())
        #expect(firstPage.objects.count == 2)
        #expect(!firstPage.nextPageToken.isEmpty)

        // Paginated AsyncSequence iteration over all matching items
        let sequence = try controlClient.listObjects(
          byItem: ListObjectsRequest().with {
            $0.parent = bucketResource
            $0.prefix = uniquePrefix
          },
          options: .init()
        )

        var foundNames = [String]()
        for try await obj in sequence {
          foundNames.append(obj.name)
        }
        #expect(foundNames.count == 3)
        #expect(foundNames.contains(file1))
        #expect(foundNames.contains(file2))
        #expect(foundNames.contains(file3))

        // Directory-like listing with delimiter
        let delimiterRequest = ListObjectsRequest().with {
          $0.parent = bucketResource
          $0.prefix = "\(uniquePrefix)/"
          $0.delimiter = "/"
        }
        let delimiterPage = try await controlClient.listObjects(
          request: delimiterRequest, options: .init())
        #expect(delimiterPage.prefixes.contains("\(uniquePrefix)/sub/"))
      } catch {
        for file in [file1, file2, file3] {
          _ = try? await controlClient.deleteObject(
            request: DeleteObjectRequest().with {
              $0.bucket = bucketResource
              $0.object = file
            },
            options: .init()
          )
        }
        throw error
      }

      // Cleanup seeded objects
      for file in [file1, file2, file3] {
        try? await controlClient.deleteObject(
          request: DeleteObjectRequest().with {
            $0.bucket = bucketResource
            $0.object = file
          },
          options: .init()
        )
      }
    }

    @Test func testObjectLifecycleAndMetadata() async throws {
      let uniqueId = UUID().uuidString
      let originalName = "test-ctrl-obj-\(uniqueId)/original.txt"
      let movedName = "test-ctrl-obj-\(uniqueId)/moved.txt"
      let content = "Hello gRPC Object Lifecycle, Metadata, and Move!"
      let data = Data(content.utf8)

      let storageClient = try StorageClient()
      let controlClient = try StorageControlClient()

      // Upload initial object
      let uploaded = try await storageClient.upload(data, to: bucketName, as: originalName).value
      #expect(uploaded.name == originalName)

      do {
        // Fetch object metadata via gRPC GetObject
        let getReq = GetObjectRequest().with {
          $0.bucket = bucketResource
          $0.object = originalName
        }
        let fetched = try await controlClient.getObject(request: getReq, options: .init())
        #expect(fetched.name == originalName)
        #expect(fetched.size == Int64(data.count))
        #expect(fetched.generation == uploaded.generation)
        #expect(fetched.metageneration == uploaded.metageneration)

        // Patch object metadata via gRPC UpdateObject
        let updateReq = UpdateObjectRequest().with {
          $0.object = Object().with {
            $0.bucket = bucketResource
            $0.name = originalName
            $0.metadata = ["test-env": "integration", "sdk-lang": "swift"]
            $0.cacheControl = "public, max-age=3600"
          }
          $0.updateMask = GoogleCloudWkt.FieldMask(paths: ["metadata", "cache_control"])
        }
        let updated = try await controlClient.updateObject(request: updateReq, options: .init())
        #expect(updated.metadata["test-env"] == "integration")
        #expect(updated.metadata["sdk-lang"] == "swift")
        #expect(updated.cacheControl == "public, max-age=3600")

        // Atomically rename/move object via gRPC MoveObject
        let moveReq = MoveObjectRequest().with {
          $0.bucket = bucketResource
          $0.sourceObject = originalName
          $0.destinationObject = movedName
        }
        let moved = try await controlClient.moveObject(request: moveReq, options: .init())
        #expect(moved.name == movedName)

        // Verify moved object exists
        let getMovedReq = GetObjectRequest().with {
          $0.bucket = bucketResource
          $0.object = movedName
        }
        let fetchedMoved = try await controlClient.getObject(request: getMovedReq, options: .init())
        #expect(fetchedMoved.name == movedName)
        #expect(fetchedMoved.size == Int64(data.count))

        // Verify source object no longer exists
        let getOriginalReq = GetObjectRequest().with {
          $0.bucket = bucketResource
          $0.object = originalName
        }
        await #expect(throws: (any Error).self) {
          try await controlClient.getObject(request: getOriginalReq, options: .init())
        }

        // Delete moved object via gRPC DeleteObject
        let deleteReq = DeleteObjectRequest().with {
          $0.bucket = bucketResource
          $0.object = movedName
        }
        try await controlClient.deleteObject(request: deleteReq, options: .init())
      } catch {
        for name in [originalName, movedName] {
          _ = try? await controlClient.deleteObject(
            request: DeleteObjectRequest().with {
              $0.bucket = bucketResource
              $0.object = name
            },
            options: .init()
          )
        }
        throw error
      }

      // Cleanup remaining objects if any
      for name in [originalName, movedName] {
        try? await controlClient.deleteObject(
          request: DeleteObjectRequest().with {
            $0.bucket = bucketResource
            $0.object = name
          },
          options: .init()
        )
      }
    }

    @Test func testDeleteObjectPreconditionFailure() async throws {
      let uniqueName = "test-ctrl-precond-\(UUID().uuidString).txt"
      let data = Data("Precondition check data".utf8)

      let storageClient = try StorageClient()
      let controlClient = try StorageControlClient()

      let uploaded = try await storageClient.upload(data, to: bucketName, as: uniqueName).value

      do {
        // Attempt delete with invalid generation precondition
        let badDeleteReq = DeleteObjectRequest().with {
          $0.bucket = bucketResource
          $0.object = uniqueName
          $0.ifGenerationMatch = uploaded.generation + 999_999
        }
        await #expect(throws: (any Error).self) {
          try await controlClient.deleteObject(request: badDeleteReq, options: .init())
        }

        // Delete with matching generation precondition
        let goodDeleteReq = DeleteObjectRequest().with {
          $0.bucket = bucketResource
          $0.object = uniqueName
          $0.ifGenerationMatch = uploaded.generation
        }
        try await controlClient.deleteObject(request: goodDeleteReq, options: .init())
      } catch {
        _ = try? await controlClient.deleteObject(
          request: DeleteObjectRequest().with {
            $0.bucket = bucketResource
            $0.object = uniqueName
          },
          options: .init()
        )
        throw error
      }

      // Ensure cleanup
      try? await controlClient.deleteObject(
        request: DeleteObjectRequest().with {
          $0.bucket = bucketResource
          $0.object = uniqueName
        },
        options: .init()
      )
    }

    @Test func testGetBucketAndListBuckets() async throws {
      let controlClient = try StorageControlClient()

      // Get Bucket Metadata
      let getReq = GetBucketRequest().with {
        $0.name = bucketResource
      }
      let bucket = try await controlClient.getBucket(request: getReq, options: .init())
      #expect(!bucket.location.isEmpty)
      #expect(!bucket.storageClass.isEmpty)
      #expect(bucket.metageneration >= 1)

      // List Buckets in Project
      let listReq = ListBucketsRequest().with {
        $0.parent = "projects/\(projectId)"
      }
      let listResponse = try await controlClient.listBuckets(request: listReq, options: .init())
      let bucketNames = listResponse.buckets.map(\.name)
      let containsTargetBucket = bucketNames.contains { $0.contains(bucketName) }
      #expect(containsTargetBucket, "Expected listed buckets to contain \(bucketName)")
    }

    @Test func testBucketIAM() async throws {
      let controlClient = try StorageControlClient()

      // Get Bucket IAM Policy
      let getPolicyReq = GoogleIAMV1.GetIamPolicyRequest().with {
        $0.resource = bucketResource
      }
      let policy = try await controlClient.getIamPolicy(request: getPolicyReq, options: .init())
      #expect(policy.version >= 1)
      #expect(!policy.etag.isEmpty)

      // Test Caller Permissions on Bucket
      let testPermsReq = GoogleIAMV1.TestIamPermissionsRequest().with {
        $0.resource = bucketResource
        $0.permissions = [
          "storage.buckets.get",
          "storage.objects.list",
          "storage.objects.get",
        ]
      }
      let permResponse = try await controlClient.testIamPermissions(
        request: testPermsReq, options: .init())
      #expect(permResponse.permissions.contains("storage.buckets.get"))
      #expect(permResponse.permissions.contains("storage.objects.list"))
    }

    @Test func testGetStorageLayout() async throws {
      let controlClient = try StorageControlClient()

      let layoutReq = GetStorageLayoutRequest().with {
        $0.name = "\(bucketResource)/storageLayout"
      }
      let layout = try await controlClient.getStorageLayout(request: layoutReq, options: .init())
      #expect(!layout.location.isEmpty)
    }

    @Test func testManagedFolderLifecycle() async throws {
      let controlClient = try StorageControlClient()
      let folderId = "test-mfolder-\(UUID().uuidString)/"
      let folderResource = "\(bucketResource)/managedFolders/\(folderId)"

      // Create Managed Folder
      let createReq = CreateManagedFolderRequest().with {
        $0.parent = bucketResource
        $0.managedFolderId = folderId
        $0.managedFolder = ManagedFolder()
      }
      let created = try await controlClient.createManagedFolder(
        request: createReq, options: .init())
      #expect(created.name.contains(folderId))

      do {
        // Get Managed Folder Metadata
        let getReq = GetManagedFolderRequest().with {
          $0.name = folderResource
        }
        let fetched = try await controlClient.getManagedFolder(request: getReq, options: .init())
        #expect(fetched.name.contains(folderId))
        #expect(fetched.metageneration >= 1)

        // List Managed Folders and verify presence
        let listReq = ListManagedFoldersRequest().with {
          $0.parent = bucketResource
        }
        let listResponse = try await controlClient.listManagedFolders(
          request: listReq, options: .init())
        let foundFolder = listResponse.managedFolders.contains { $0.name.contains(folderId) }
        #expect(
          foundFolder, "Expected listManagedFolders to contain newly created folder \(folderId)")

        // Delete Managed Folder
        let deleteReq = DeleteManagedFolderRequest().with {
          $0.name = folderResource
        }
        try await controlClient.deleteManagedFolder(request: deleteReq, options: .init())
      } catch {
        _ = try? await controlClient.deleteManagedFolder(
          request: DeleteManagedFolderRequest().with {
            $0.name = folderResource
          },
          options: .init()
        )
        throw error
      }

      // Ensure cleanup
      try? await controlClient.deleteManagedFolder(
        request: DeleteManagedFolderRequest().with {
          $0.name = folderResource
        },
        options: .init()
      )
    }
  }

#endif
