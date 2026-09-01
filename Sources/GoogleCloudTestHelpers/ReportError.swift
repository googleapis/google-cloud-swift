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
import GoogleCloudGax
import InMemoryLogging
import Logging

public func runLoggedTest(_ name: String, _ test: (Logger) async throws -> Void) async throws {
  let handler = InMemoryLogHandler()
  let logger = Logger(label: "logging.test", factory: { (String) in handler })
  do {
    try await test(logger)
  } catch let e as GoogleCloudGax.RequestError {
    try reportRequestError(name, error: e, handler: handler)
  } catch {
    try reportError(name, error: error, handler: handler)
  }
}

func reportRequestError(
  _ name: String, error: GoogleCloudGax.RequestError, handler: InMemoryLogHandler
) throws {
  for entry in handler.entries {
    print("\(entry.message)")
  }
  if case let .http(details) = error {
    let p = String(data: details.payload, encoding: .utf8)!
    print("### \(name) HTTP error=\(error)\npayload=\(p)")
  } else if case let .service(e) = error {
    print("### \(name) Service error=\(e)")
  } else {
    print("### \(name) error=\(error)")
  }
  throw error
}

func reportError(
  _ name: String, error: any Error, handler: InMemoryLogHandler
) throws {
  for entry in handler.entries {
    print("\(entry.message)")
  }
  print("### \(name) error=\(error)")
  throw error
}
