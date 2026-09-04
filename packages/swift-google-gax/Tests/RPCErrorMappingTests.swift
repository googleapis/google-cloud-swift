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
import GRPCCore
import GRPCProtobuf
import GoogleCloudGax
@testable import GoogleCloudGaxGRPC
import GoogleCloudWKT
import GoogleRpc
import SwiftProtobuf
import Testing

@Suite struct RPCErrorMappingTests {
  @Test func mapsAllStatusCodes() {
    let cases: [(RPCError.Code, GoogleRpc.Code)] = [
      (.cancelled, .cancelled),
      (.unknown, .unknown),
      (.invalidArgument, .invalidArgument),
      (.deadlineExceeded, .deadlineExceeded),
      (.notFound, .notFound),
      (.alreadyExists, .alreadyExists),
      (.permissionDenied, .permissionDenied),
      (.resourceExhausted, .resourceExhausted),
      (.failedPrecondition, .failedPrecondition),
      (.aborted, .aborted),
      (.outOfRange, .outOfRange),
      (.unimplemented, .unimplemented),
      (.internalError, .internal),
      (.unavailable, .unavailable),
      (.dataLoss, .dataLoss),
      (.unauthenticated, .unauthenticated),
    ]

    for (rpcCode, expectedRpcCode) in cases {
      let rpcError = RPCError(code: rpcCode, message: "Error for \(rpcCode)")
      let requestError = rpcError.toRequestError()

      guard case let .service(serviceError) = requestError else {
        Issue.record("Expected .service error for \(rpcCode), got \(requestError)")
        continue
      }
      #expect(serviceError.code == expectedRpcCode)
      #expect(serviceError.message == "Error for \(rpcCode)")
      #expect(serviceError.details.isEmpty)
    }
  }

  @Test func mapsCauseToIOError() {
    struct CustomUnderlyingError: Error, Equatable {}
    let rpcError = RPCError(
      code: .unavailable,
      message: "Connection lost",
      cause: CustomUnderlyingError()
    )
    let requestError = rpcError.toRequestError()

    guard case let .io(error) = requestError else {
      Issue.record("Expected .io error, got \(requestError)")
      return
    }
    guard let underlying = error as? RPCError else {
      Issue.record("Expected RPCError wrapped in .io, got \(error)")
      return
    }
    #expect(underlying.code == .unavailable)
    #expect(underlying.message == "Connection lost")
    #expect(underlying.cause is CustomUnderlyingError)
  }

  @Test func mapsBadContentTypeToIOError() {
    var metadata = Metadata()
    metadata.replaceOrAddString("text/html", forKey: "content-type")
    let rpcError = RPCError(code: .unknown, message: "Bad gateway", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .io(error) = requestError else {
      Issue.record("Expected .io error, got \(requestError)")
      return
    }
    guard let badContentType = error as? BadContentTypeError else {
      Issue.record("Expected BadContentTypeError, got \(error)")
      return
    }
    #expect(badContentType.contentType == "text/html")
    #expect(badContentType.rpcError.code == .unknown)
    #expect(
      badContentType.description.contains("unexpected value in content-type header 'text/html'"))
  }

  @Test func allowsGrpcContentType() {
    var metadata = Metadata()
    metadata.replaceOrAddString("application/grpc", forKey: "content-type")
    let rpcError = RPCError(code: .notFound, message: "Resource not found", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.code == .notFound)
    #expect(serviceError.message == "Resource not found")
  }

  @Test func allowsGrpcWithSuffixContentType() {
    var metadata = Metadata()
    metadata.replaceOrAddString("application/grpc+proto", forKey: "content-type")
    let rpcError = RPCError(code: .notFound, message: "Resource not found", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.code == .notFound)
  }

  @Test func decodesStatusDetailsErrorInfo() throws {
    let status = GoogleRPCStatus(
      code: .unauthenticated,
      message: "Detailed unauthenticated message",
      details: [
        .errorInfo(
          reason: "API_KEY_INVALID",
          domain: "googleapis.com",
          metadata: ["service": "storage.googleapis.com"]
        )
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .unauthenticated, message: "Fallback message", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.code == .unauthenticated)
    #expect(serviceError.message == "Detailed unauthenticated message")
    #expect(serviceError.details.count == 1)

    guard case let .errorInfo(errorInfo) = serviceError.details[0] else {
      Issue.record("Expected .errorInfo detail, got \(serviceError.details[0])")
      return
    }
    #expect(errorInfo.reason == "API_KEY_INVALID")
    #expect(errorInfo.domain == "googleapis.com")
    #expect(errorInfo.metadata == ["service": "storage.googleapis.com"])
  }

  @Test func decodesStatusDetailsBadRequest() throws {
    let violation = ErrorDetails.BadRequest.FieldViolation(
      field: "bucket_name",
      description: "Invalid bucket name format",
      reason: "INVALID_FORMAT",
      localizedMessage: ErrorDetails.LocalizedMessage(
        locale: "en-US",
        message: "The bucket name contains illegal characters."
      )
    )
    let status = GoogleRPCStatus(
      code: .invalidArgument,
      message: "Invalid bucket name",
      details: [.badRequest(violations: [violation])]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .invalidArgument, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.code == .invalidArgument)
    #expect(serviceError.details.count == 1)

    guard case let .badRequest(badRequest) = serviceError.details[0] else {
      Issue.record("Expected .badRequest detail, got \(serviceError.details[0])")
      return
    }
    #expect(badRequest.fieldViolations.count == 1)
    #expect(badRequest.fieldViolations[0].field == "bucket_name")
    #expect(badRequest.fieldViolations[0].description == "Invalid bucket name format")
    #expect(badRequest.fieldViolations[0].reason == "INVALID_FORMAT")
    #expect(badRequest.fieldViolations[0].localizedMessage?.locale == "en-US")
    #expect(
      badRequest.fieldViolations[0].localizedMessage?.message
        == "The bucket name contains illegal characters."
    )
  }

  @Test func decodesStatusDetailsRetryInfo() throws {
    let status = GoogleRPCStatus(
      code: .unavailable,
      message: "Service temporarily unavailable",
      details: [
        .retryInfo(delay: .seconds(5) + .nanoseconds(500_000_000))
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .unavailable, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.code == .unavailable)
    #expect(serviceError.details.count == 1)

    guard case let .retryInfo(retryInfo) = serviceError.details[0] else {
      Issue.record("Expected .retryInfo detail, got \(serviceError.details[0])")
      return
    }
    #expect(retryInfo.retryDelay?.seconds == 5)
    #expect(retryInfo.retryDelay?.nanos == 500_000_000)
  }

  @Test func decodesStatusDetailsDebugInfo() throws {
    let status = GoogleRPCStatus(
      code: .internalError,
      message: "Internal error",
      details: [
        .debugInfo(
          stack: ["frame1.swift:10", "frame2.swift:20"],
          detail: "Internal invariant violated"
        )
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .internalError, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 1)

    guard case let .debugInfo(debugInfo) = serviceError.details[0] else {
      Issue.record("Expected .debugInfo detail, got \(serviceError.details[0])")
      return
    }
    #expect(debugInfo.stackEntries == ["frame1.swift:10", "frame2.swift:20"])
    #expect(debugInfo.detail == "Internal invariant violated")
  }

  @Test func decodesStatusDetailsHelp() throws {
    let status = GoogleRPCStatus(
      code: .permissionDenied,
      message: "Permission denied",
      details: [
        .help(
          links: [
            ErrorDetails.Help.Link(
              url: "https://cloud.google.com/storage",
              description: "API Documentation"
            )
          ]
        )
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .permissionDenied, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 1)

    guard case let .help(help) = serviceError.details[0] else {
      Issue.record("Expected .help detail, got \(serviceError.details[0])")
      return
    }
    #expect(help.links.count == 1)
    #expect(help.links[0].description == "API Documentation")
    #expect(help.links[0].url == "https://cloud.google.com/storage")
  }

  @Test func decodesStatusDetailsLocalizedMessage() throws {
    let status = GoogleRPCStatus(
      code: .notFound,
      message: "Not found",
      details: [
        .localizedMessage(
          locale: "en-US",
          message: "Resource not found"
        )
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .notFound, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 1)

    guard case let .localizedMessage(localized) = serviceError.details[0] else {
      Issue.record("Expected .localizedMessage detail, got \(serviceError.details[0])")
      return
    }
    #expect(localized.locale == "en-US")
    #expect(localized.message == "Resource not found")
  }

  @Test func decodesStatusDetailsPreconditionFailure() throws {
    let status = GoogleRPCStatus(
      code: .failedPrecondition,
      message: "Precondition failed",
      details: [
        .preconditionFailure(
          violations: [
            ErrorDetails.PreconditionFailure.Violation(
              type: "TOS",
              subject: "google.com/cloud",
              description: "Terms of service not accepted"
            )
          ]
        )
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .failedPrecondition, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 1)

    guard case let .preconditionFailure(precondition) = serviceError.details[0] else {
      Issue.record("Expected .preconditionFailure detail, got \(serviceError.details[0])")
      return
    }
    #expect(precondition.violations.count == 1)
    #expect(precondition.violations[0].type == "TOS")
    #expect(precondition.violations[0].subject == "google.com/cloud")
    #expect(precondition.violations[0].description == "Terms of service not accepted")
  }

  @Test func decodesStatusDetailsQuotaFailure() throws {
    let status = GoogleRPCStatus(
      code: .resourceExhausted,
      message: "Resource exhausted",
      details: [
        .quotaFailure(
          violations: [
            ErrorDetails.QuotaFailure.Violation(
              subject: "project:12345",
              description: "Rate limit exceeded"
            )
          ]
        )
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .resourceExhausted, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 1)

    guard case let .quotaFailure(quota) = serviceError.details[0] else {
      Issue.record("Expected .quotaFailure detail, got \(serviceError.details[0])")
      return
    }
    #expect(quota.violations.count == 1)
    #expect(quota.violations[0].subject == "project:12345")
    #expect(quota.violations[0].description == "Rate limit exceeded")
  }

  @Test func decodesStatusDetailsRequestInfo() throws {
    let status = GoogleRPCStatus(
      code: .internalError,
      message: "Internal failure",
      details: [
        .requestInfo(
          requestID: "req-12345678",
          servingData: "serving-data-token"
        )
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .internalError, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 1)

    guard case let .requestInfo(requestInfo) = serviceError.details[0] else {
      Issue.record("Expected .requestInfo detail, got \(serviceError.details[0])")
      return
    }
    #expect(requestInfo.requestId == "req-12345678")
    #expect(requestInfo.servingData == "serving-data-token")
  }

  @Test func decodesStatusDetailsResourceInfo() throws {
    let status = GoogleRPCStatus(
      code: .notFound,
      message: "Bucket not found",
      details: [
        .resourceInfo(
          type: "storage.googleapis.com/Bucket",
          name: "projects/_/buckets/my-bucket",
          errorDescription: "Bucket not found",
          owner: "project:my-project"
        )
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .notFound, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 1)

    guard case let .resourceInfo(resourceInfo) = serviceError.details[0] else {
      Issue.record("Expected .resourceInfo detail, got \(serviceError.details[0])")
      return
    }
    #expect(resourceInfo.resourceType == "storage.googleapis.com/Bucket")
    #expect(resourceInfo.resourceName == "projects/_/buckets/my-bucket")
    #expect(resourceInfo.owner == "project:my-project")
    #expect(resourceInfo.description == "Bucket not found")
  }

  @Test func decodesStatusDetailsUnknownAny() throws {
    var anyProto = Google_Protobuf_Any()
    anyProto.typeURL = "type.googleapis.com/custom.unknown.Message"
    anyProto.value = Data([0x08, 0x96, 0x01])

    let status = GoogleRPCStatus(
      code: .unknown,
      message: "Custom error",
      details: [.any(anyProto)]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .unknown, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 1)

    guard case let .other(other) = serviceError.details[0] else {
      Issue.record("Expected .other detail, got \(serviceError.details[0])")
      return
    }
    #expect(other.typeUrl == "type.googleapis.com/custom.unknown.Message")
  }

  @Test func fallsBackOnCorruptedDetails() {
    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      [0xFF, 0xFF, 0xFF],  // Invalid protobuf wire bytes
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .invalidArgument, message: "Invalid argument", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error on corrupted details, got \(requestError)")
      return
    }
    #expect(serviceError.code == .invalidArgument)
    #expect(serviceError.message == "Invalid argument")
    #expect(serviceError.details.isEmpty)
  }

  @Test func decodesMultipleDetails() throws {
    let status = GoogleRPCStatus(
      code: .resourceExhausted,
      message: "Quota exceeded",
      details: [
        .errorInfo(
          reason: "RESOURCE_EXHAUSTED",
          domain: "googleapis.com"
        ),
        .retryInfo(delay: .seconds(30)),
      ]
    )

    var metadata = Metadata()
    metadata.replaceOrAddBinary(
      try status.serializedBytes(),
      forKey: "grpc-status-details-bin"
    )

    let rpcError = RPCError(code: .resourceExhausted, message: "Fallback", metadata: metadata)
    let requestError = rpcError.toRequestError()

    guard case let .service(serviceError) = requestError else {
      Issue.record("Expected .service error, got \(requestError)")
      return
    }
    #expect(serviceError.details.count == 2)
    guard case .errorInfo = serviceError.details[0] else {
      Issue.record("Expected .errorInfo, got \(serviceError.details[0])")
      return
    }
    guard case .retryInfo = serviceError.details[1] else {
      Issue.record("Expected .retryInfo, got \(serviceError.details[1])")
      return
    }
  }
}
