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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// An unauthenticated credentials source that provides no authentication headers.
///
/// Anonymous credentials do not supply any token or API key to the request. They are useful
/// for accessing public Google Cloud resources that do not require authentication (such as
/// public Cloud Storage buckets or public BigQuery datasets), or when connecting to local
/// service emulators that do not enforce authentication.
struct AnonymousCredentials: CredentialsProvider {
  func headers() async throws -> AuthHeaders {
    // Dummy empty implementation for skeleton phase
    return []
  }

  func universeDomain() async -> String? {
    return nil
  }
}
