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
import GoogleCloudWKT
import GoogleRpc

extension Operation {
  // Extracts the state of an operation.
  public func _extractStatus<Response>(_ type: Response.Type) throws
    -> GoogleCloudGax._PollableOperationImpl<Response>.State
  where Response: GoogleCloudWKT._AnyPackable {
    guard self.done else {
      return .init(done: false, result: nil)
    }

    switch self.result {
    case .response(let anyValue):
      guard let anyValueUnwrapped = anyValue else {
        return .init(
          done: true,
          result: .failure(
            GoogleCloudGax.RequestError.binding(
              "Operation completed but response value was missing")))
      }
      let response = try Response(fromAny: anyValueUnwrapped)
      return .init(done: true, result: .success(response))
    case .error(let status):
      return Self._extractError(Response.self, status: status)
    case .none:
      return Self._missingResult(Response.self)
    }
  }

  public func _extractStatusEmpty() throws
    -> GoogleCloudGax._PollableOperationImpl<Swift.Void>.State
  {
    guard self.done else {
      return .init(done: false, result: nil)
    }

    switch self.result {
    case .response:
      return .init(done: true, result: .success(()))
    case .error(let status):
      return Self._extractError(Swift.Void.self, status: status)
    case .none:
      return Self._missingResult(Swift.Void.self)
    }
  }

  static func _extractError<T>(_ type: T.Type, status: GoogleRpc.Status?)
    -> GoogleCloudGax._PollableOperationImpl<T>.State
  {
    guard let statusUnwrapped = status else {
      return .init(
        done: true,
        result: .failure(
          GoogleCloudGax.RequestError.binding(
            "Operation completed but error value was missing")))
    }
    let error = GoogleCloudGax.RequestError.service(
      GoogleCloudGax.ServiceError(
        code: GoogleRpc.Code(intValue: Int(statusUnwrapped.code)),
        message: statusUnwrapped.message))
    return .init(done: true, result: .failure(error))
  }

  static func _missingResult<T>(_ type: T.Type) -> GoogleCloudGax._PollableOperationImpl<T>.State {
    .init(
      done: true,
      result: .failure(
        GoogleCloudGax.RequestError.binding("Operation completed but result was missing")))
  }
}
