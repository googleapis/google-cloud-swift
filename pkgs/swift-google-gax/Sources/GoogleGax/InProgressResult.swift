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

/// The result of an in-progress polling loop control decision.
///
/// Application developers only need to use this type when implementing their own polling policies.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum InProgressResult: Sendable {
  /// The operation is still in progress and within policy limits; continue polling.
  case keepPolling

  /// The operation is still in progress, but the polling policy is stopping the loop.
  ///
  /// Polling policies may stop the loop if limits (such as elapsed time or attempt count)
  /// are exhausted.
  case exhausted(RequestError)
}
