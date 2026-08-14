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

extension RequestError: Equatable {
  public static func == (lhs: RequestError, rhs: RequestError) -> Bool {
    switch (lhs, rhs) {
    case (.binding(let l), .binding(let r)): return l == r
    case (.http(let l), .http(let r)): return l == r
    case (.io(let l), .io(let r)):
      if let el = l as? RequestError, let er = r as? RequestError {
        return el == er
      }
      return false
    case (.service(let l), .service(let r)): return l == r
    case (.unimplemented, .unimplemented): return true
    case (.exhausted(let l), .exhausted(let r)): return l == r
    case (.malformedResponse(let l), .malformedResponse(let r)): return l == r
    default: return false
    }
  }
}

extension HTTPDetails: Equatable {
  public static func == (lhs: HTTPDetails, rhs: HTTPDetails) -> Bool {
    return lhs.http_status_code == rhs.http_status_code && lhs.headers == rhs.headers
      && lhs.payload == rhs.payload
  }
}

extension ServiceError: Equatable {
  public static func == (lhs: ServiceError, rhs: ServiceError) -> Bool {
    return lhs.code == rhs.code && lhs.message == rhs.message
  }
}

extension LimitedElapsedTimeError: Equatable {
  public static func == (lhs: LimitedElapsedTimeError, rhs: LimitedElapsedTimeError) -> Bool {
    return lhs.maximumDuration == rhs.maximumDuration && lhs.source == rhs.source
  }
}
