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
import GoogleRpc
import GoogleCloudWKT

/// Additional information accompanying service errors.
public enum StatusDetail: Equatable, Sendable {
  /// Describes violations in a client request.
  ///
  /// See [BadRequest][google_cloud_rpc::model::BadRequest] for more information.
  case badRequest(GoogleRpc.BadRequest)

  /// Describes additional debugging info.
  ///
  /// See [DebugInfo][google_cloud_rpc::model::DebugInfo] for more information.
  case debugInfo(GoogleRpc.DebugInfo)

  /// Describes the cause of the error with structured details.
  ///
  /// See [ErrorInfo][google_cloud_rpc::model::ErrorInfo] for more information.
  case errorInfo(GoogleRpc.ErrorInfo)

  /// Provides links to documentation or for performing an out of band action.
  ///
  /// See [Help][google_cloud_rpc::model::Help] for more information.
  case help(GoogleRpc.Help)

  /// Provides a localized error message that is safe to return to the user.
  ///
  /// See [LocalizedMessage][google_cloud_rpc::model::LocalizedMessage] for more information.
  case localizedMessage(GoogleRpc.LocalizedMessage)

  /// Describes what preconditions have failed.
  ///
  /// See [PreconditionFailure][google_cloud_rpc::model::PreconditionFailure] for more information.
  case preconditionFailure(GoogleRpc.PreconditionFailure)

  /// Describes a single quota violation.
  ///
  /// See [QuotaFailure][google_cloud_rpc::model::QuotaFailure] for more information.
  case quotaFailure(GoogleRpc.QuotaFailure)

  /// Contains metadata about the request that clients can attach when filing a bug.
  ///
  /// See [RequestInfo][google_cloud_rpc::model::RequestInfo] for more information.
  case requestInfo(GoogleRpc.RequestInfo)

  /// Describes the resource that is being accessed.
  ///
  /// See [ResourceInfo][google_cloud_rpc::model::ResourceInfo] for more information.
  case resourceInfo(GoogleRpc.ResourceInfo)

  /// Describes when the clients can retry a failed request.
  ///
  /// See [RetryInfo][google_cloud_rpc::model::RetryInfo] for more information.
  case retryInfo(GoogleRpc.RetryInfo)

  /// Other details (represented as Any).
  case other(GoogleCloudWKT.`Any`)
}

extension StatusDetail {
  init(from: GoogleCloudWKT.`Any`) {
    if let v = try? GoogleRpc.BadRequest(fromAny: from) {
      self = .badRequest(v)
    } else if let v = try? GoogleRpc.DebugInfo(fromAny: from) {
      self = .debugInfo(v)
    } else if let v = try? GoogleRpc.ErrorInfo(fromAny: from) {
      self = .errorInfo(v)
    } else if let v = try? GoogleRpc.Help(fromAny: from) {
      self = .help(v)
    } else if let v = try? GoogleRpc.LocalizedMessage(fromAny: from) {
      self = .localizedMessage(v)
    } else if let v = try? GoogleRpc.PreconditionFailure(fromAny: from) {
      self = .preconditionFailure(v)
    } else if let v = try? GoogleRpc.QuotaFailure(fromAny: from) {
      self = .quotaFailure(v)
    } else if let v = try? GoogleRpc.RequestInfo(fromAny: from) {
      self = .requestInfo(v)
    } else if let v = try? GoogleRpc.ResourceInfo(fromAny: from) {
      self = .resourceInfo(v)
    } else if let v = try? GoogleRpc.RetryInfo(fromAny: from) {
      self = .retryInfo(v)
    } else {
      self = .other(from)
    }
  }
}
