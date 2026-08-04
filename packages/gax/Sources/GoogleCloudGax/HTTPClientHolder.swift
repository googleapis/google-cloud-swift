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

import class AsyncHTTPClient.HTTPClient
import struct AsyncHTTPClient.HTTPClientRequest
import struct AsyncHTTPClient.HTTPClientResponse
import struct Logging.Logger

/// Automatically call shutdown() on a HTTPClient.
///
/// HTTPClient requires an (asynchronous) call to `shutdown()` or it leaks resources.
/// This class automates the call.
///
/// SAFETY: calling `shutdown()` requires all requests to be finished. In the AuthHTTPClient struct
/// each HTTP request is executed within a function, therefore the object is live while the HTTP
/// request is in progress. By the time deinit starts, all starting a call requires having a
/// reference to the object, so shutdown
final class HTTPClientHolder: HTTPClientProtocol {
  let inner = AsyncHTTPClient.HTTPClient()
  deinit {
    // Use a background task to shutdown the inner client. In most cases, the application will
    // continue running and the HTTPClient is shutdown "eventually". Except for (maybe) some false
    // positives in leak detectors, there is no harm if the application terminates before this gets
    // to run.
    let copy = inner
    Task {
      // Note how we make a copy of `inner` to avoid capturing `self`.
      do {
        try await copy.shutdown()
      } catch {
        // Ignore any exceptions. If `shutdown()` failed there is nothing the application can do.
      }
    }
  }

  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    try await self.inner.execute(request, timeout: .init(timeout), logger: nil)
  }
}
