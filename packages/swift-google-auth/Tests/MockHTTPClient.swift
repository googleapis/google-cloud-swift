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

import Synchronization
import struct DequeModule.Deque
import struct Logging.Logger
import AsyncHTTPClient
import Testing
@testable import GoogleCloudAuth

final class MockHTTPClient: HTTPClientProtocol {
  typealias Closure = @Sendable (HTTPClientRequest) async throws -> HTTPClientResponse
  enum MockError: Error, Sendable {
    case empty
  }

  let responses: Mutex<Deque<Closure>>

  init(_ responses: [Closure]) {
    self.responses = Mutex(Deque(responses))
  }

  deinit {
    #expect(responses.withLock { $0.isEmpty })
  }

  public func execute(request: HTTPClientRequest, timeout: Duration, logger: Logger?) async throws
    -> HTTPClientResponse
  {
    guard let closure = self.responses.withLock({ $0.popFirst() }) else {
      throw MockError.empty
    }
    return try await closure(request)
  }
}
