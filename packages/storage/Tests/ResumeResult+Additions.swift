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
import GoogleCloudStorage

extension ResumeResult: Equatable {
  public static func == (lhs: ResumeResult, rhs: ResumeResult) -> Bool {
    switch (lhs, rhs) {
    case (.permanent(let l), .permanent(let r)): return isEquivalent(l, r)
    case (.exhausted(let l), .exhausted(let r)): return isEquivalent(l, r)
    case (.resume(let l), .resume(let r)): return isEquivalent(l, r)
    default: return false
    }
  }

  private static func isEquivalent(_ lhs: RequestError, _ rhs: RequestError) -> Bool {
    switch (lhs, rhs) {
    case (.http(let l), .http(let r)):
      return l.http_status_code == r.http_status_code
    case (.service(let l), .service(let r)):
      return l.code == r.code
    case (.io(let l), .io(let r)):
      return (l as NSError) == (r as NSError)
    case (.binding(let l), .binding(let r)):
      return l == r
    case (.exhausted, .exhausted):
      return true
    case (.unimplemented, .unimplemented):
      return true
    case (.malformedResponse, .malformedResponse):
      return true
    default:
      return false
    }
  }
}
