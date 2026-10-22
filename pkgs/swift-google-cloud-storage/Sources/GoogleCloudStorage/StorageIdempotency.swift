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
import GoogleIAMV1
import GoogleLongRunning

package let idempotencyToken = "x-goog-gcs-idempotency-token"

func resolveStorageIdempotency(
  isIdempotent: Bool,
  isMutating: Bool,
  options: GoogleGax.RequestOptions
) -> GoogleGax.RequestOptions {
  var options = options
  let effectiveIdempotency = options.idempotent ?? isIdempotent
  options.idempotent = effectiveIdempotency
  if isMutating && effectiveIdempotency {
    if options.headers[idempotencyToken] == nil {
      options.headers[idempotencyToken] = UUID().uuidString
    }
  }
  return options
}

extension GetBucketRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListBucketsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only list request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension GetObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListObjectsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only list request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension CreateBucketRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Inserting a bucket is always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: true, options: options)
  }
}

extension DeleteBucketRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Deleting a bucket is always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: true, options: options)
  }
}

extension LockBucketRetentionPolicyRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Locking a bucket retention policy is always idempotent per the Cloud Storage retry strategy
    // specification when the required ifMetagenerationMatch precondition (> 0) is populated.
    let isIdempotent = self.ifMetagenerationMatch > 0
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension UpdateBucketRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Updating a bucket is conditionally idempotent per the Cloud Storage retry strategy
    // specification when ifMetagenerationMatch is set.
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension ComposeObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Composing an object is conditionally idempotent per the Cloud Storage retry strategy
    // specification when ifGenerationMatch is set on the destination object.
    let isIdempotent = self.ifGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension DeleteObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Deleting an object is conditionally idempotent per the Cloud Storage retry strategy
    // specification when ifGenerationMatch or a specific generation number is set.
    let isIdempotent = self.generation != 0 || self.ifGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension RestoreObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Restoring a soft-deleted object is conditionally idempotent when ifGenerationMatch or
    // ifMetagenerationMatch is set.
    let isIdempotent = self.ifGenerationMatch != nil || self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension UpdateObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Updating object metadata is conditionally idempotent per the Cloud Storage retry strategy
    // specification when ifMetagenerationMatch is set.
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension RewriteObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Rewriting an object is conditionally idempotent per the Cloud Storage retry strategy
    // specification when ifGenerationMatch is set on the destination object.
    let isIdempotent = self.ifGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension MoveObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Moving an object is conditionally idempotent when both destination ifGenerationMatch and
    // source ifSourceGenerationMatch preconditions are set.
    let isIdempotent = self.ifGenerationMatch != nil && self.ifSourceGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension GoogleIAMV1.GetIamPolicyRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension GoogleIAMV1.SetIamPolicyRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Setting an IAM policy is conditionally idempotent per the Cloud Storage retry strategy
    // specification when the policy includes a non-empty etag precondition.
    let isIdempotent = !(self.policy?.etag.isEmpty ?? true)
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension GoogleIAMV1.TestIamPermissionsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Testing IAM permissions is read-only and always idempotent per the Cloud Storage retry
    // strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension CreateFolderRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Creating a folder is idempotent when requestId is provided (auto-populated by
    // StorageControlClient); the backend joins retries via requestId rather than the header.
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension DeleteFolderRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Deleting a folder is conditionally idempotent when ifMetagenerationMatch is set.
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension GetFolderRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListFoldersRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only list request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension RenameFolderRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Renaming a folder is conditionally idempotent when ifMetagenerationMatch is set.
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension DeleteFolderRecursiveRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Deleting a folder recursively is conditionally idempotent when ifMetagenerationMatch is set.
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension GetStorageLayoutRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension CreateManagedFolderRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Creating a managed folder is idempotent when requestId is provided (auto-populated by
    // StorageControlClient); the backend joins retries via requestId rather than the header.
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension DeleteManagedFolderRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Deleting a managed folder is conditionally idempotent when ifMetagenerationMatch is set.
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension GetManagedFolderRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListManagedFoldersRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only list request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension UpdateManagedFolderRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Updating a managed folder is conditionally idempotent when ifMetagenerationMatch is set.
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension CreateAnywhereCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension UpdateAnywhereCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension DisableAnywhereCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension PauseAnywhereCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension ResumeAnywhereCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension GetAnywhereCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListAnywhereCachesRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only list request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension CreateRapidCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension UpdateRapidCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension DisableRapidCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension GetRapidCacheRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListRapidCachesRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only list request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension GetProjectIntelligenceConfigRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension UpdateProjectIntelligenceConfigRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension GetFolderIntelligenceConfigRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension UpdateFolderIntelligenceConfigRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension GetOrganizationIntelligenceConfigRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension UpdateOrganizationIntelligenceConfigRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Per the proto specification, this request is only idempotent if a requestId is provided
    // (auto-populated by StorageControlClient).
    let isIdempotent = !self.requestId.isEmpty
    return resolveStorageIdempotency(
      isIdempotent: isIdempotent, isMutating: false, options: options)
  }
}

extension GetIntelligenceFindingRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListIntelligenceFindingsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only list request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension SummarizeIntelligenceFindingsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only summarize request; always idempotent per the Cloud Storage retry strategy
    // specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension GetIntelligenceFindingRevisionRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListIntelligenceFindingRevisionsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only list request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ViewObjectFullContextRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only view request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension GoogleLongRunning.GetOperationRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    // Read-only get request; always idempotent per the Cloud Storage retry strategy specification.
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}
