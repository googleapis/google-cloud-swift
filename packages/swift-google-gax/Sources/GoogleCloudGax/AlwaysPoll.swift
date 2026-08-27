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

/// A polling policy that continues polling on all errors.
///
/// This policy must be decorated to limit the number of polling attempts or the duration of the
/// polling loop.
///
/// The policy continues on all errors. This may be useful in tests, or to just poll for a fix
/// number of attempts or fixed amount of time.
final public class AlwaysPoll: PollingErrorPolicy {
  public init() {}

  public func onError(state: PollingState, error: RequestError) -> PollingResult {
    .retry(error)
  }
}
