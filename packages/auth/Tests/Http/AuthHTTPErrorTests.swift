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
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import GoogleCloudAuth

@Suite struct AuthHTTPErrorTest {
  private let testURL = URL(string: "https://example.com")!

  @Test func unsuccessfulResponseAccessors() {
    let response = HTTPURLResponse(
      url: testURL,
      statusCode: 403,
      httpVersion: nil,
      headerFields: ["X-Custom-Header": "CustomValue"]
    )!
    let bodyString = "Forbidden Access"
    let data = Data(bodyString.utf8)

    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: data)

    #expect(error.statusCode == 403)
    #expect(error.body == bodyString)
    #expect(error.bodyData == data)
    #expect(error.headers?["X-Custom-Header"] == "CustomValue")
    #expect(error.urlError == nil)
  }

  @Test func transportErrorAccessors() {
    let urlError = URLError(.timedOut)
    let error = AuthHTTPError.transportError(urlError)

    #expect(error.urlError == urlError)
    #expect(error.statusCode == nil)
    #expect(error.body == nil)
    #expect(error.bodyData == nil)
    #expect(error.headers == nil)
  }

  @Test func decodingErrorAccessors() {
    let decodingError = DecodingError.valueNotFound(
      String.self,
      DecodingError.Context(codingPath: [], debugDescription: "Test")
    )
    let testData = Data("Invalid JSON".utf8)
    let error = AuthHTTPError.decodingError(error: decodingError, data: testData)

    #expect(error.urlError == nil)
    #expect(error.statusCode == nil)
    #expect(error.body == "Invalid JSON")
    #expect(error.bodyData == testData)
    #expect(error.headers == nil)
  }

  @Test func unknownErrorAccessors() {
    let genericError = URLError(.unknown)
    let error = AuthHTTPError.unknown(genericError)

    #expect(error.urlError == nil)
    #expect(error.statusCode == nil)
    #expect(error.body == nil)
    #expect(error.bodyData == nil)
    #expect(error.headers == nil)
  }

  @Test func invalidUTF8ResponseAccessors() {
    let error = AuthHTTPError.invalidUTF8Response

    #expect(error.urlError == nil)
    #expect(error.statusCode == nil)
    #expect(error.body == nil)
    #expect(error.bodyData == nil)
    #expect(error.headers == nil)
  }
}
