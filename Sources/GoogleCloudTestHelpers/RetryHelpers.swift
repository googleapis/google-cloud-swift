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
import GoogleCloudGax

/// Shared RequestOptions for integration tests that retry non-idempotent operations
/// and enforce a 15-second attempt timeout to prevent premature exhaustion of retry loop budgets.
public let testRetryOptions = RequestOptions().with {
  $0.idempotency = true
  $0.attemptTimeout = .seconds(15)
}

extension RequestError {
  public var isAlreadyExists: Bool {
    switch self {
    case .service(let err):
      return err.code == .alreadyExists || err.httpStatusCode == 409
    case .http(let details):
      return details.httpStatusCode == 409
    case .exhausted(let details):
      return details.source.isAlreadyExists
    default:
      return false
    }
  }

  public var isNotFound: Bool {
    switch self {
    case .service(let err):
      return err.code == .notFound || err.httpStatusCode == 404
    case .http(let details):
      return details.httpStatusCode == 404
    case .exhausted(let details):
      return details.source.isNotFound
    default:
      return false
    }
  }

  public var isFailedPreconditionOrAborted: Bool {
    switch self {
    case .service(let err):
      return err.code == .failedPrecondition || err.code == .aborted || err.httpStatusCode == 412
        || err.httpStatusCode == 409
    case .http(let details):
      return details.httpStatusCode == 412 || details.httpStatusCode == 409
    case .exhausted(let details):
      return details.source.isFailedPreconditionOrAborted
    default:
      return false
    }
  }
}

extension Swift.Error {
  public var isAlreadyExists: Bool {
    (self as? RequestError)?.isAlreadyExists ?? false
  }
  public var isNotFound: Bool {
    (self as? RequestError)?.isNotFound ?? false
  }
  public var isFailedPreconditionOrAborted: Bool {
    (self as? RequestError)?.isFailedPreconditionOrAborted ?? false
  }
}
