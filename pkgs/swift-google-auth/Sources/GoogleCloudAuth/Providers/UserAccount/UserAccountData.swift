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

/// Represents the raw `authorized_user` JSON credential file format.
struct UserAccountData: Sendable, Codable {
  let type: String
  let clientId: String
  let clientSecret: String
  let refreshToken: String
  let tokenUri: String?
  let quotaProjectId: String?

  init(
    type: String,
    clientId: String,
    clientSecret: String,
    refreshToken: String,
    tokenUri: String? = nil,
    quotaProjectId: String? = nil
  ) {
    self.type = type
    self.clientId = clientId
    self.clientSecret = clientSecret
    self.refreshToken = refreshToken
    self.tokenUri = tokenUri
    self.quotaProjectId = quotaProjectId
  }
}
