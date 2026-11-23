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
import GoogleAuth
import GoogleCloudPubSub
@_spi(GoogleCloudInternal) import GoogleGax
import GoogleRpc
import GoogleWKT
import PubSubConformanceProtos
import SwiftProtobuf

enum ConformanceHelpers {
  static func makeClientOptions(endpoint: String, useEmulatorEnv: Bool) throws
    -> GoogleGax.ClientOptions
  {
    var clientOptions = GoogleGax.ClientOptions()
    if !endpoint.isEmpty {
      clientOptions.endpoint = endpoint.contains("://") ? endpoint : "http://\(endpoint)"
      clientOptions.credentials = try GoogleAuth.Credentials(configuration: .anonymous)
    } else if !useEmulatorEnv {
      clientOptions.credentials = try GoogleAuth.Credentials(configuration: .anonymous)
    }
    return clientOptions
  }

  static func googleRpcCode(from raw: Int32) -> GoogleRpc.Code? {
    switch raw {
    case 0: return .ok
    case 1: return .cancelled
    case 2: return .unknown
    case 3: return .invalidArgument
    case 4: return .deadlineExceeded
    case 5: return .notFound
    case 6: return .alreadyExists
    case 7: return .permissionDenied
    case 8: return .resourceExhausted
    case 9: return .failedPrecondition
    case 10: return .aborted
    case 11: return .outOfRange
    case 12: return .unimplemented
    case 13: return .internal
    case 14: return .unavailable
    case 15: return .dataLoss
    case 16: return .unauthenticated
    default: return nil
    }
  }

  static func makeRequestOptions(
    customHeaders: [String: String],
    retryCodes: [Int32],
    hasTotalTimeoutMs: Bool,
    totalTimeoutMs: Int64,
    hasMaxAttempts: Bool,
    maxAttempts: Int32,
    hasInitialDelayMs: Bool,
    initialDelayMs: Int64,
    hasMaxDelayMs: Bool,
    maxDelayMs: Int64,
    hasMultiplier: Bool,
    multiplier: Double
  ) throws -> GoogleGax.RequestOptions {
    var options = GoogleGax.RequestOptions()
    if !customHeaders.isEmpty {
      options.headers = GoogleGax.HTTPHeaders(customHeaders.map { ($0.key, $0.value) })
    }

    if !retryCodes.isEmpty || hasTotalTimeoutMs || hasMaxAttempts {
      var policy = PubSubRetryPolicy()
      if !retryCodes.isEmpty {
        policy.retryableCodes = Set(retryCodes.compactMap(Self.googleRpcCode(from:)))
      }
      if hasTotalTimeoutMs {
        policy.timeLimit = .milliseconds(max(0, totalTimeoutMs))
      }
      if hasMaxAttempts {
        policy.maxAttempts = Int(max(1, maxAttempts))
      }
      options.retryPolicy = policy
    }

    if hasInitialDelayMs || hasMaxDelayMs || hasMultiplier {
      let initial =
        hasInitialDelayMs
        ? Duration.milliseconds(max(1, initialDelayMs)) : Duration.milliseconds(100)
      let requestedMax =
        hasMaxDelayMs ? Duration.milliseconds(max(1, maxDelayMs)) : Duration.seconds(60)
      let effectiveMax = max(initial, requestedMax)
      let scaling = hasMultiplier ? max(1.0, multiplier) : 1.3
      options.backoffPolicy = try GoogleGax.ExponentialBackoff(
        initialDelay: initial,
        maximumDelay: effectiveMax,
        scaling: scaling
      )
    }

    return options
  }

  static func mapErrorToGRPC(_ error: any Error) -> (code: Int32, message: String) {
    if let pubSubError = error as? PubSubError {
      switch pubSubError {
      case .publisherShutDown, .orderingKeyPaused:
        return (9, pubSubError.description)
      case .messageTooLarge, .invalidUTF8Attribute, .emptyProjectID, .invalidConfiguration:
        return (3, pubSubError.description)
      case .flowControlLimitExceeded:
        return (8, pubSubError.description)
      case .mismatchedMessageIDCount:
        return (13, pubSubError.description)
      case .settlementFailed(let ackError):
        return Self.mapAckErrorToGRPC(ackError)
      @unknown default:
        return (2, "\(error)")
      }
    }

    if let reqError = error as? GoogleGax.RequestError {
      switch reqError {
      case .service(let svc):
        return (Int32(svc.code.intValue ?? 2), svc.message)
      case .exhausted(let exhausted):
        if let underlying = exhausted.underlyingError {
          return Self.mapErrorToGRPC(underlying)
        }
        if case .elapsedTime = exhausted {
          return (4, reqError.description)
        }
        return (2, reqError.description)
      case .unimplemented:
        return (12, reqError.description)
      case .io:
        return (14, reqError.description)
      case .http(let details):
        let code = GoogleRpc.Code(httpStatusCode: details.statusCode)
        return (Int32(code.intValue ?? 2), reqError.description)
      case .binding, .badURL:
        return (3, reqError.description)
      case .malformedResponse:
        return (13, reqError.description)
      @unknown default:
        return (2, reqError.description)
      }
    }

    if error is CancellationError {
      return (1, "Cancelled")
    }
    return (2, "\(error)")
  }

  static func mapAckErrorToGRPC(_ ackError: AckError) -> (code: Int32, message: String) {
    switch ackError.status {
    case .success:
      return (0, "")
    case .permissionDenied:
      return (7, ackError.message)
    case .failedPrecondition:
      return (9, ackError.message)
    case .invalidAckID:
      return (3, ackError.message)
    case .other:
      if let underlying = ackError.underlyingError {
        return Self.mapErrorToGRPC(underlying)
      }
      return (2, ackError.message)
    @unknown default:
      return (2, ackError.message)
    }
  }

  static func mapSettlementStatus(
    _ status: SettlementStatus
  ) -> Pubsub_Conformance_V1_SettlementResultEvent.AckStatus {
    switch status {
    case .success:
      return .success
    case .permissionDenied:
      return .permissionDenied
    case .failedPrecondition:
      return .failedPrecondition
    case .invalidAckID:
      return .invalidAckID
    case .other:
      return .other
    @unknown default:
      return .unknown
    }
  }

  static func mapSettlementError(
    _ error: any Error
  ) -> (
    status: Pubsub_Conformance_V1_SettlementResultEvent.AckStatus,
    grpcCode: Int32,
    message: String
  ) {
    if case .settlementFailed(let ackError) = error as? PubSubError {
      let (code, msg) = Self.mapAckErrorToGRPC(ackError)
      return (Self.mapSettlementStatus(ackError.status), code, msg)
    }
    let (code, msg) = Self.mapErrorToGRPC(error)
    switch code {
    case 7:
      return (.permissionDenied, code, msg)
    case 9:
      return (.failedPrecondition, code, msg)
    case 14:
      return (.unavailable, code, msg)
    default:
      return (.other, code, msg)
    }
  }

  static func toProtoTimestamp(_ wkt: GoogleWKT.WKTTimestamp)
    -> SwiftProtobuf.Google_Protobuf_Timestamp
  {
    var ts = SwiftProtobuf.Google_Protobuf_Timestamp()
    ts.seconds = wkt.seconds
    ts.nanos = wkt.nanos
    return ts
  }
}
