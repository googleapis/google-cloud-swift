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

/// Provides OIDC subject tokens.
public protocol SubjectTokenProvider: Sendable {
  /// Retrieves a fresh OIDC subject token from the source.
  ///
  /// This will be called when a valid OIDC subject token is needed
  /// (e.g., when the SDK needs to exchange it for a Google Cloud access token).
  ///
  /// After the auth library obtains the subject token,
  /// it will be immediately exchanged for a short-lived access token, then discarded.
  ///
  /// - Returns: A valid, raw OIDC subject token string (typically a JWT or ID token).
  func subjectToken() async throws -> String
}
