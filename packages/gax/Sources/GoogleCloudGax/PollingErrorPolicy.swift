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
import GoogleRpc

/// Determines how errors are handled in the LRO polling loop.
///
/// The client libraries automatically poll long-running operations (LROs) until the operation
/// succeeds or fails, or "completes". Sometimes polling the operation may fail, the failure may be
/// a transient problem, something that may be resolved in a future polling attempt, or a
/// unrecoverable error. For example, a `404 - NOT FOUND` status indicates the operation no longer
/// exists, more polling won't resolve the issue, whereas `429 - TOO MANY REQUESTS` indicates a busy
/// service, which may resolve by the next attempt.
///
/// Note that polling errors are distinct from errors in the operation itself. If the operation
/// fails, polling succeeds, and the response indicates the details of the failure.
public protocol PollingErrorPolicy: Sendable {
  /// Query the polling policy after an error.
  ///
  /// - Parameters:
  ///   - state: The state of the retry loop.
  ///   - error: The last error when attempting the request.
  /// - Returns: The result of the polling decision.
  func onError(state: PollingState, error: RequestError) -> PollingResult

  /// Query the policy after successfully polling the LRO.
  ///
  /// Polling policies may use this to update telemetry counters, or log the event, or otherwise
  ///
  /// - Parameters
  /// - `state` - the current state of the polling loop.
  func onInProgress(state: PollingState) throws
}

extension PollingErrorPolicy {
  /// By default, this method is a no-op.
  public func onInProgress(state: PollingState) throws {}
}
