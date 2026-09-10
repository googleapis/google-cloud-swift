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
import SystemPackage
import Testing

@testable import GoogleCloudAuth

@Suite("ADC Path Resolution Tests")
struct ADCPathTests {
  @Test("ADC well-known path Windows")
  func wellKnownPathWindows() {
    let env = ["APPDATA": "C:/Users/foo"]
    let path = resolveWellKnownADCPathWindows(environment: env)

    // Check the string directly as FilePath normalizes to the OS
    var expected = FilePath("C:/Users/foo")
    expected.append("gcloud")
    expected.append("application_default_credentials.json")
    #expect(path == expected)
  }

  @Test("ADC well-known path Windows no APPDATA")
  func wellKnownPathWindowsNoAppData() {
    let env: [String: String] = [:]
    let path = resolveWellKnownADCPathWindows(environment: env)
    #expect(path == nil)
  }

  @Test("ADC well-known path POSIX")
  func wellKnownPathPOSIX() {
    let env = ["HOME": "/home/foo"]
    let path = resolveWellKnownADCPathPOSIX(environment: env)

    var expected = FilePath("/home/foo")
    expected.append(".config")
    expected.append("gcloud")
    expected.append("application_default_credentials.json")
    #expect(path == expected)
  }

  @Test("ADC well-known path POSIX no HOME")
  func wellKnownPathPOSIXNoHome() {
    let env: [String: String] = [:]
    let path = resolveWellKnownADCPathPOSIX(environment: env)
    #expect(path == nil)
  }

  @Test("ADC path from environment")
  func pathFromEnv() {
    let env = ["GOOGLE_APPLICATION_CREDENTIALS": "/foo/bar.json"]
    let path = resolveADCPath(environment: env)
    #expect(path == .environmentVariable(FilePath("/foo/bar.json")))
  }
}
