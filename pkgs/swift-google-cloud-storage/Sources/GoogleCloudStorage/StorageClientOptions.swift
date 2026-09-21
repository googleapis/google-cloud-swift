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

public import GoogleGax

/// Configuration options for ``StorageClient``.
public struct StorageClientOptions: Sendable {
  /// Common options used by all Google Swift SDK clients.
  public var client: GoogleGax.ClientOptions

  /// Default configuration inherited by `writeObject` operations.
  public var writeObject: WriteObjectOptions

  /// Default configuration inherited by `readObject` operations.
  public var readObject: ReadObjectOptions

  public init(
    client: GoogleGax.ClientOptions = .init(),
    writeObject: WriteObjectOptions = .default,
    readObject: ReadObjectOptions = .default
  ) {
    self.client = client
    self.writeObject = writeObject
    self.readObject = readObject
  }

  /// Override specific values using closure modification.
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}
