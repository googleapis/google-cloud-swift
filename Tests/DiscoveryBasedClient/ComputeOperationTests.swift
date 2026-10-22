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
      #expect(serviceError.message == "fail")
      #expect(!serviceError.details.isEmpty)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func throwErrorsOperationErrorMessageFallbacks() throws {
    let opCodeAndMessage = GoogleCloudComputeV1.Operation().with {
      $0.error = GoogleCloudComputeV1.Operation.Error().with {
        $0.errors = [
          GoogleCloudComputeV1.Operation.Error.Errors().with {
            $0.code = "QUOTA_EXCEEDED"
            $0.message = "Quota 'CPUS' exceeded."
          },
          GoogleCloudComputeV1.Operation.Error.Errors().with {
            $0.code = "RESOURCE_NOT_READY"
          },
        ]
      }
    }
    do {
      try opCodeAndMessage._detectErrors()
      Issue.record("Expected RequestError.service to be thrown")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.message == "QUOTA_EXCEEDED: Quota 'CPUS' exceeded.\nRESOURCE_NOT_READY")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let opEmptyErrors = GoogleCloudComputeV1.Operation().with {
      $0.httpErrorMessage = ""
      $0.error = GoogleCloudComputeV1.Operation.Error().with {
        $0.errors = [GoogleCloudComputeV1.Operation.Error.Errors()]
      }
    }
    do {
      try opEmptyErrors._detectErrors()
      Issue.record("Expected RequestError.service to be thrown")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.message == "Operation failed")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func throwErrorsMapsStructuredErrorDetails() throws {
    let quotaExceeded = GoogleCloudComputeV1.QuotaExceededInfo().with {
      $0.metricName = "compute.googleapis.com/cpus"
      $0.limitName = "CPUS-per-project"
      $0.limit = 24.0
      $0.dimensions = ["region": "us-central1"]
    }
    let errorEntry = GoogleCloudComputeV1.Operation.Error.Errors().with {
      $0.code = "QUOTA_EXCEEDED"
      $0.location = "resources.disks"
      $0.message = "Quota 'CPUS' exceeded. Limit: 24.0 in region us-central1."
      $0.errorDetails = [
        GoogleCloudComputeV1.Operation.Error.Errors.ErrorDetails().with {
          $0.errorInfo = GoogleCloudComputeV1.ErrorInfo().with {
            $0.reason = "QUOTA_EXCEEDED"
            $0.domain = "compute.googleapis.com"
            $0.metadatas = ["metric": "cpus"]
          }
          $0.help = GoogleCloudComputeV1.Help().with {
            $0.links = [
              GoogleCloudComputeV1.HelpLink().with {
                $0.description = "Request more quota"
                $0.url = "https://cloud.google.com/compute/quotas"
              }
            ]
          }
          $0.localizedMessage = GoogleCloudComputeV1.LocalizedMessage().with {
            $0.locale = "en-US"
            $0.message = "CPU quota exceeded in us-central1."
          }
          $0.quotaInfo = quotaExceeded
        }
      ]
    }
    let operation = GoogleCloudComputeV1.Operation().with {
      $0.httpErrorStatusCode = 403
      $0.httpErrorMessage = "FORBIDDEN"
      $0.error = GoogleCloudComputeV1.Operation.Error().with {
        $0.errors = [errorEntry]
      }
    }

    do {
      try operation._detectErrors()
      Issue.record("Expected RequestError.service to be thrown")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.code == .permissionDenied)
      #expect(serviceError.httpStatusCode == 403)
      #expect(serviceError.message == "FORBIDDEN")
      #expect(serviceError.details.count == 5)

      let expectedErrorInfo = GoogleRpc.ErrorInfo().with {
        $0.reason = "QUOTA_EXCEEDED"
        $0.domain = "compute.googleapis.com"
        $0.metadata = ["metric": "cpus"]
      }
      let expectedHelp = GoogleRpc.Help().with {
        $0.links = [
          GoogleRpc.Help.Link().with {
            $0.description = "Request more quota"
            $0.url = "https://cloud.google.com/compute/quotas"
          }
        ]
      }
      let expectedLocalized = GoogleRpc.LocalizedMessage().with {
        $0.locale = "en-US"
        $0.message = "CPU quota exceeded in us-central1."
      }

      #expect(serviceError.details[0] == .errorInfo(expectedErrorInfo))
      #expect(serviceError.details[1] == .help(expectedHelp))
      #expect(serviceError.details[2] == .localizedMessage(expectedLocalized))

      if case .other(let anyQuota) = serviceError.details[3] {
        let unpackedQuota = try GoogleCloudComputeV1.QuotaExceededInfo(fromAny: anyQuota)
        #expect(unpackedQuota == quotaExceeded)
      } else {
        Issue.record("Expected 4th detail to be .other(QuotaExceededInfo)")
      }

      if case .other(let anyEntry) = serviceError.details[4] {
        let unpackedEntry = try GoogleCloudComputeV1.Operation.Error.Errors(fromAny: anyEntry)
        #expect(unpackedEntry == errorEntry)
      } else {
        Issue.record("Expected 5th detail to be .other(Operation.Error.Errors)")
      }
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
    final class MockInstances: Clients.InstancesProtocol, @unchecked Sendable {
      var insertPollingOptionsCalled = false
      func insertPollingUntilDone(
        request: InstancesClient.InsertRequest, options: GoogleGax.RequestOptions
      ) async throws -> GoogleCloudComputeV1.Operation {
        insertPollingOptionsCalled = true
        return GoogleCloudComputeV1.Operation()
      }
    }

    let mock = MockInstances()
    _ = try await mock.insertPollingUntilDone(request: InstancesClient.InsertRequest())
    #expect(mock.insertPollingOptionsCalled)

    mock.insertPollingOptionsCalled = false
    _ = try await mock.insertPollingUntilDone(
      project: "test-project",
      zone: "us-central1-a",
      body: nil
    )
    #expect(mock.insertPollingOptionsCalled)
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
