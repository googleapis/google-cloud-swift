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
import Testing
@_spi(GoogleCloudInternal) import GoogleCloudGax
import GoogleRpc

@Suite struct ErrorWrapperTests {
  @Test func validStatus() throws {
    let json = Data(
      """
      {
        "error": {
          "code": 400,
          "status": "INVALID_ARGUMENT",
          "message": "invalid argument message",
          "details": []
        }
      }
      """.utf8)

    guard let wrapper = _ErrorWrapper(data: json) else {
      Issue.record("Failed to decode ErrorWrapper")
      return
    }

    let serviceError = ServiceError(wrapper: wrapper)
    #expect(serviceError.code == .invalidArgument)
    #expect(serviceError.message == "invalid argument message")
  }

  @Test func nilStatus() throws {
    let json = Data(
      """
      {
        "error": {
          "code": 500,
          "message": "internal error message",
          "details": []
        }
      }
      """.utf8)

    guard let wrapper = _ErrorWrapper(data: json) else {
      Issue.record("Failed to decode ErrorWrapper")
      return
    }

    let serviceError = ServiceError(wrapper: wrapper)
    #expect(serviceError.code == .internal)
    #expect(serviceError.httpStatusCode == 500)
    #expect(serviceError.message == "internal error message")
  }

  @Test func httpStatusFallbackWithoutDetails() throws {
    let cases: [(Int, GoogleRpc.Code)] = [
      (400, .invalidArgument),
      (401, .unauthenticated),
      (403, .permissionDenied),
      (404, .notFound),
      (409, .alreadyExists),
      (412, .failedPrecondition),
      (429, .resourceExhausted),
      (499, .cancelled),
      (500, .internal),
      (501, .unimplemented),
      (503, .unavailable),
      (504, .deadlineExceeded),
      (418, .unknown),
    ]

    for (httpCode, expectedRpcCode) in cases {
      let json = Data(
        """
        {
          "error": {
            "code": \(httpCode),
            "message": "error message for \(httpCode)"
          }
        }
        """.utf8)

      guard let wrapper = _ErrorWrapper(data: json) else {
        Issue.record("Failed to decode ErrorWrapper for httpCode \(httpCode)")
        continue
      }

      let serviceError = ServiceError(wrapper: wrapper)
      #expect(serviceError.code == expectedRpcCode)
      #expect(serviceError.httpStatusCode == httpCode)
      #expect(serviceError.message == "error message for \(httpCode)")
      #expect(serviceError.details.isEmpty)
    }
  }

  @Test func unknownStatus() throws {
    let json = Data(
      """
      {
        "error": {
          "code": 500,
          "status": "SOME_UNKNOWN_STATUS",
          "message": "unknown status message",
          "details": []
        }
      }
      """.utf8)

    guard let wrapper = _ErrorWrapper(data: json) else {
      Issue.record("Failed to decode ErrorWrapper")
      return
    }

    let serviceError = ServiceError(wrapper: wrapper)
    #expect(serviceError.code == .unknownStringValue("SOME_UNKNOWN_STATUS"))
    #expect(serviceError.message == "unknown status message")
  }

  @Test func missingDetails() throws {
    let json = Data(
      """
      {
        "error": {
          "code": 400,
          "status": "INVALID_ARGUMENT",
          "message": "missing details message"
        }
      }
      """.utf8)

    guard let wrapper = _ErrorWrapper(data: json) else {
      Issue.record("Failed to decode ErrorWrapper")
      return
    }

    let serviceError = ServiceError(wrapper: wrapper)
    #expect(serviceError.code == .invalidArgument)
    #expect(serviceError.message == "missing details message")
    #expect(serviceError.details.isEmpty)
  }

  @Test func withHelpDetails() throws {
    let json = Data(
      """
      {
        "error": {
          "code": 400,
          "status": "INVALID_ARGUMENT",
          "message": "message with help details",
          "details": [
            {
              "@type": "type.googleapis.com/google.rpc.Help",
              "links": [
                {
                  "description": "Google developers console API activation",
                  "url": "https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project"
                }
              ]
            }
          ]
        }
      }
      """.utf8)

    guard let wrapper = _ErrorWrapper(data: json) else {
      Issue.record("Failed to decode ErrorWrapper")
      return
    }

    let serviceError = ServiceError(wrapper: wrapper)
    #expect(serviceError.code == .invalidArgument)
    #expect(serviceError.message == "message with help details")
    #expect(serviceError.details.count == 1)

    let wantDetails: [StatusDetail] = [
      .help(
        Help().with {
          $0.links = [
            Help.Link().with {
              $0.description = "Google developers console API activation"
              $0.url =
                "https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project"
            }
          ]
        })
    ]

    #expect(serviceError.details == wantDetails)
  }
}
