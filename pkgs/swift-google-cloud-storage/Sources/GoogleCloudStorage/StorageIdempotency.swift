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

package let idempotencyToken = "x-goog-gcs-idempotency-token"

func resolveStorageIdempotency(
  isIdempotent: Bool,
  isMutating: Bool,
  options: GoogleGax.RequestOptions
) -> GoogleGax.RequestOptions {
  var options = options
  let effectiveIdempotency = options.idempotency ?? isIdempotent
  options.idempotency = effectiveIdempotency
  if isMutating && effectiveIdempotency {
    if options.headers[idempotencyToken] == nil {
      options.headers[idempotencyToken] = UUID().uuidString
    }
  }
  return options
}

extension GetBucketRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListBucketsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension GetObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension ListObjectsRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveStorageIdempotency(isIdempotent: true, isMutating: false, options: options)
  }
}

extension CreateBucketRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    resolveStorageIdempotency(isIdempotent: true, isMutating: true, options: options)
  }
}

extension DeleteBucketRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension LockBucketRetentionPolicyRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.ifMetagenerationMatch > 0
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension UpdateBucketRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension ComposeObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.ifGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension DeleteObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.generation != 0 || self.ifGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension RestoreObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.ifGenerationMatch != nil || self.ifMetagenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension UpdateObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.ifMetagenerationMatch != nil || self.ifGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension RewriteObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.ifGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}

extension MoveObjectRequest {
  package func resolveIdempotency(options: GoogleGax.RequestOptions) -> GoogleGax.RequestOptions {
    let isIdempotent = self.ifGenerationMatch != nil && self.ifSourceGenerationMatch != nil
    return resolveStorageIdempotency(isIdempotent: isIdempotent, isMutating: true, options: options)
  }
}
