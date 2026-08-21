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

/// The result of a resume decision by a ``ResumePolicy``.
public enum ResumeResult: Sendable {
  /// The error is non-recoverable (e.g. invalid arguments, precondition failed); stop the transfer.
  case permanent(RequestError)

  /// The error was recoverable, but the policy has exhausted its limits (e.g. too many consecutive errors or timeout).
  case exhausted(RequestError)

  /// The error is recoverable; resume the transfer from the last committed offset after backing off.
  case resume(RequestError)
}
