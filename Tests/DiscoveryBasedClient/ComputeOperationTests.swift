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

import Testing
@testable import GoogleCloudComputeV1
import GoogleGax
import GoogleRpc
import GoogleWKT

@Suite struct ComputeOperationTests {
  private static let httpStatusMappings: [(Int32, GoogleRpc.Code)] = [
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
    (599, .unknown),
  ]

  @Test func throwErrorsNoError() throws {
    let operation = GoogleCloudComputeV1.Operation()
    try operation._detectErrors()
  }

  @Test(arguments: httpStatusMappings)
  func throwErrorsHttpStatusCode(mapping: (Int32, GoogleRpc.Code)) throws {
    let (statusCode, expectedCode) = mapping
    let operation = GoogleCloudComputeV1.Operation().with {
      $0.httpErrorStatusCode = statusCode
      $0.httpErrorMessage = "Error \(statusCode)"
    }
    do {
      try operation._detectErrors()
      Issue.record("Expected RequestError.service to be thrown")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == expectedCode)
      #expect(serviceError.httpStatusCode == Int(statusCode))
      #expect(serviceError.message == "Error \(statusCode)")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func throwErrorsOperationErrorWithoutStatusCode() throws {
    let operation = GoogleCloudComputeV1.Operation().with {
      $0.error = GoogleCloudComputeV1.Operation.Error().with {
        $0.errors = [GoogleCloudComputeV1.Operation.Error.Errors().with { $0.message = "fail" }]
      }
    }
    do {
      try operation._detectErrors()
      Issue.record("Expected RequestError.service to be thrown")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == .unknown)
      #expect(serviceError.httpStatusCode == nil)
      #expect(serviceError.message == "Operation failed")
      #expect(!serviceError.details.isEmpty)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func throwErrorsHttpErrorMessageWithoutStatusCode() throws {
    let operation = GoogleCloudComputeV1.Operation().with {
      $0.httpErrorStatusCode = 0
      $0.httpErrorMessage = "Custom failure message"
    }
    do {
      try operation._detectErrors()
      Issue.record("Expected RequestError.service to be thrown")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == .unknown)
      #expect(serviceError.httpStatusCode == nil)
      #expect(serviceError.message == "Custom failure message")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func throwErrorsBulkInsertError() throws {
    let operation = GoogleCloudComputeV1.Operation().with {
      $0.instancesBulkInsertOperationMetadata = InstancesBulkInsertOperationMetadata().with {
        $0.perLocationStatus = [
          "loc": BulkInsertOperationStatus().with { $0.failedToCreateVmCount = 1 }
        ]
      }
    }
    do {
      try operation._detectErrors()
      Issue.record("Expected RequestError.service to be thrown")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == .unknown)
      #expect(serviceError.message == "Instances bulk insert operation failed")
      #expect(!serviceError.details.isEmpty)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func throwErrorsSetMetadataError() throws {
    let operation = GoogleCloudComputeV1.Operation().with {
      $0.setCommonInstanceMetadataOperationMetadata = SetCommonInstanceMetadataOperationMetadata()
        .with {
          $0.perLocationOperations = [
            "loc": SetCommonInstanceMetadataOperationMetadataPerLocationOperationInfo().with {
              $0.error = GoogleCloudComputeV1.Status().with { $0.message = "fail" }
            }
          ]
        }
    }
    do {
      try operation._detectErrors()
      Issue.record("Expected RequestError.service to be thrown")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == .unknown)
      #expect(serviceError.message == "Set common instance metadata operation failed")
      #expect(!serviceError.details.isEmpty)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func protocolDispatchesPollingUntilDone() async throws {
    struct MockPoller: PollableOperation {
      typealias ResponseType = GoogleCloudComputeV1.Operation
      func wait() async throws -> GoogleCloudComputeV1.Operation {
        GoogleCloudComputeV1.Operation()
      }
    }

    final class MockInstances: Clients.InstancesProtocol, @unchecked Sendable {
      var insertPollingOptionsCalled = false
      func insertPollingUntilDone(
        request: InstancesClient.InsertRequest, options: GoogleGax.RequestOptions
      ) async throws -> any GoogleGax.PollableOperation<GoogleCloudComputeV1.Operation> {
        insertPollingOptionsCalled = true
        return MockPoller()
      }
    }

    let mock = MockInstances()
    let poller = try await mock.insertPollingUntilDone(request: InstancesClient.InsertRequest())
    #expect(mock.insertPollingOptionsCalled)
    _ = try await poller.wait()

    mock.insertPollingOptionsCalled = false
    let poller2 = try await mock.insertPollingUntilDone(
      project: "test-project",
      zone: "us-central1-a",
      body: nil
    )
    #expect(mock.insertPollingOptionsCalled)
    _ = try await poller2.wait()
  }

  @Test func enumStringValueIsNonOptional() {
    let status: GoogleCloudComputeV1.Operation.Status = .done
    let str: Swift.String = status.stringValue
    #expect(str == "DONE")
    let unknown: GoogleCloudComputeV1.Operation.Status = .unknownStringValue("CUSTOM")
    let unknownStr: Swift.String = unknown.stringValue
    #expect(unknownStr == "CUSTOM")
  }
}
