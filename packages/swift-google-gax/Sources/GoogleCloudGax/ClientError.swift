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

/// Represents an error while trying to initialize a client.
public enum ClientError: Error {
  /// The endpoint string does not represent a valid URL.
  ///
  /// ## Troubleshooting
  ///
  /// The most common cause for this error is an invalid value in the `endpoint` client
  /// option.
  ///
  /// Review the configuration for your client.
  case invalidEndpoint(String)
}
