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

import GoogleCloudGax

extension RetryResult: Equatable {
  public static func == (lhs: RetryResult, rhs: RetryResult) -> Bool {
    switch (lhs, rhs) {
    case (.permanent(let l), .permanent(let r)): return l == r
    case (.exhausted(let l), .exhausted(let r)): return l == r
    case (.retry(let l), .retry(let r)): return l == r
    default: return false
    }
  }
}
