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
import GoogleCloudWKT
import GoogleCloudWKTConvert
import GoogleRpc
import SwiftProtobuf

/// An error indicating that the server returned an unexpected `Content-Type` header that does not start with `application/grpc`.
struct BadContentTypeError: Error, Sendable, CustomStringConvertible, Equatable {
  /// The unexpected `Content-Type` value received from the server.
  let contentType: String
  /// The underlying RPC error.
  let rpcError: RPCError

  init(contentType: String, rpcError: RPCError) {
    self.contentType = contentType
    self.rpcError = rpcError
  }

  var description: String {
    "unexpected value in content-type header '\(self.contentType)', should start with application/grpc. In Google Cloud, this is a common problem when using an invalid endpoint, or an endpoint that does not support the target gRPC service."
  }
}

extension StatusDetail {
  init(_ detail: ErrorDetails) {
    if let info = detail.errorInfo {
      var item = GoogleRpc.ErrorInfo()
      item.reason = info.reason
      item.domain = info.domain
      item.metadata = info.metadata
      self = .errorInfo(item)
    } else if let badRequest = detail.badRequest {
      var item = GoogleRpc.BadRequest()
      item.fieldViolations = badRequest.violations.map { v in
        var violation = GoogleRpc.BadRequest.FieldViolation()
        violation.field = v.field
        violation.description = v.violationDescription
        violation.reason = v.reason
        if let lm = v.localizedMessage {
          var localized = GoogleRpc.LocalizedMessage()
          localized.locale = lm.locale
          localized.message = lm.message
          violation.localizedMessage = localized
        }
        return violation
      }
      self = .badRequest(item)
    } else if let debugInfo = detail.debugInfo {
      var item = GoogleRpc.DebugInfo()
      item.stackEntries = debugInfo.stack
      item.detail = debugInfo.detail
      self = .debugInfo(item)
    } else if let help = detail.help {
      var item = GoogleRpc.Help()
      item.links = help.links.map { l in
        var link = GoogleRpc.Help.Link()
        link.description = l.linkDescription
        link.url = l.url
        return link
      }
      self = .help(item)
    } else if let localizedMessage = detail.localizedMessage {
      var item = GoogleRpc.LocalizedMessage()
      item.locale = localizedMessage.locale
      item.message = localizedMessage.message
      self = .localizedMessage(item)
    } else if let preconditionFailure = detail.preconditionFailure {
      var item = GoogleRpc.PreconditionFailure()
      item.violations = preconditionFailure.violations.map { v in
        var violation = GoogleRpc.PreconditionFailure.Violation()
        violation.type = v.type
        violation.subject = v.subject
        violation.description = v.violationDescription
        return violation
      }
      self = .preconditionFailure(item)
    } else if let quotaFailure = detail.quotaFailure {
      var item = GoogleRpc.QuotaFailure()
      item.violations = quotaFailure.violations.map { v in
        var violation = GoogleRpc.QuotaFailure.Violation()
        violation.subject = v.subject
        violation.description = v.violationDescription
        violation.apiService = v.apiService
        violation.quotaMetric = v.quotaMetric
        violation.quotaId = v.quotaID
        violation.quotaDimensions = v.quotaDimensions
        violation.quotaValue = Int64(v.quotaValue)
        violation.futureQuotaValue = v.futureQuotaValue.map(Int64.init)
        return violation
      }
      self = .quotaFailure(item)
    } else if let requestInfo = detail.requestInfo {
      var item = GoogleRpc.RequestInfo()
      item.requestId = requestInfo.requestID
      item.servingData = requestInfo.servingData
      self = .requestInfo(item)
    } else if let resourceInfo = detail.resourceInfo {
      var item = GoogleRpc.ResourceInfo()
      item.resourceType = resourceInfo.type
      item.resourceName = resourceInfo.name
      item.owner = resourceInfo.owner
      item.description = resourceInfo.errorDescription
      self = .resourceInfo(item)
    } else if let retryInfo = detail.retryInfo {
      var item = GoogleRpc.RetryInfo()
      let seconds = retryInfo.delay.components.seconds
      let nanos = Int64(retryInfo.delay.components.attoseconds / 1_000_000_000)
      item.retryDelay = try? GoogleCloudWKT.Duration(seconds: seconds, nanos: nanos)
      self = .retryInfo(item)
    } else if let protoAny = detail.any {
      if let wktAny = try? GoogleCloudWKT.Any(proto: protoAny) {
        self = .other(wktAny)
      } else {
        self = .other(fallbackAny(typeUrl: protoAny.typeURL))
      }
    } else {
      self = .other(fallbackAny())
    }
  }
}

private func fallbackAny(typeUrl: String = "") -> GoogleCloudWKT.`Any` {
  let json = "{\"@type\":\"\(typeUrl)\"}".data(using: .utf8) ?? Data()
  if let any = try? JSONDecoder().decode(GoogleCloudWKT.`Any`.self, from: json) {
    return any
  }
  do {
    return try GoogleCloudWKT.`Any`(fromMessage: GoogleCloudWKT.Empty())
  } catch {
    fatalError("Failed to construct fallback GoogleCloudWKT.Any: \(error)")
  }
}

extension RPCError {
  /// Converts an `RPCError` to a `GoogleCloudGax.RequestError`.
  func toRequestError() -> RequestError {
    if self.cause != nil {
      return .io(self)
    }

    if let contentType = self.metadata[stringValues: "content-type"].first(where: { _ in true }),
      !contentType.starts(with: "application/grpc")
    {
      return .io(BadContentTypeError(contentType: contentType, rpcError: self))
    }

    if let googleStatus = try? self.unpackGoogleRPCStatus() {
      let code = GoogleRpc.Code(intValue: googleStatus.code.rawValue)
      let message = googleStatus.message.isEmpty ? self.message : googleStatus.message
      let details = googleStatus.details.map { StatusDetail($0) }
      return .service(ServiceError(code: code, message: message, details: details))
    }

    let code = GoogleRpc.Code(intValue: self.code.rawValue)
    return .service(ServiceError(code: code, message: self.message, details: []))
  }
}
