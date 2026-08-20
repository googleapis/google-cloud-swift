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
import GoogleCloudWkt
import GoogleRpc
@testable import GoogleCloudGax

@Suite struct StatusDetailTests {
  @Test func badRequest() throws {
    let input = BadRequest()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .badRequest(got) = detail else {
      Issue.record("Expected .badRequest, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func debugInfo() throws {
    let input = DebugInfo()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .debugInfo(got) = detail else {
      Issue.record("Expected .debugInfo, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func errorInfo() throws {
    let input = ErrorInfo()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .errorInfo(got) = detail else {
      Issue.record("Expected .errorInfo, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func help() throws {
    let input = Help()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .help(got) = detail else {
      Issue.record("Expected .help, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func localizedMessage() throws {
    let input = LocalizedMessage()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .localizedMessage(got) = detail else {
      Issue.record("Expected .localizedMessage, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func preconditionFailure() throws {
    let input = PreconditionFailure()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .preconditionFailure(got) = detail else {
      Issue.record(
        "Expected .preconditionFailure, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func quotaFailure() throws {
    var input = QuotaFailure()
    input.violations = [
      QuotaFailure.Violation().with {
        $0.subject = "subject"
        $0.description = "desc"
        $0.apiService = "service"
      }
    ]
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .quotaFailure(got) = detail else {
      Issue.record("Expected .quotaFailure, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func requestInfo() throws {
    let input = RequestInfo()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .requestInfo(got) = detail else {
      Issue.record("Expected .requestInfo, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func resourceInfo() throws {
    let input = ResourceInfo()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .resourceInfo(got) = detail else {
      Issue.record("Expected .resourceInfo, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func retryInfo() throws {
    let input = RetryInfo()
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .retryInfo(got) = detail else {
      Issue.record("Expected .retryInfo, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == input)
  }

  @Test func other() throws {
    let input = GoogleCloudWkt.Api()  // A valid message, but unexpected in status details.
    let asAny = try GoogleCloudWkt.`Any`(fromMessage: input)
    let detail = StatusDetail(from: asAny)
    guard case let .other(got) = detail else {
      Issue.record("Expected .other, detail=\(detail), asAny=\(asAny), input=\(input)")
      return
    }
    #expect(got == asAny)
  }
}
