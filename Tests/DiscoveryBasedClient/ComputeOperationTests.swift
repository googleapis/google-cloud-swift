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
import GoogleCloudGax
import GoogleRpc
import GoogleCloudWKT

@Suite struct ComputeOperationTests {
  @Test func throwErrorsNoError() throws {
    let operation = GoogleCloudComputeV1.Operation()
    try operation._detectErrors()
  }

  @Test func throwErrorsGenericError() throws {
    let operation = GoogleCloudComputeV1.Operation().with {
      $0.httpErrorStatusCode = 404
      $0.httpErrorMessage = "Not Found"
    }
    #expect(throws: RequestError.self) {
      try operation._detectErrors()
    }
  }

  @Test func throwErrorsOperationError() throws {
    let operation = GoogleCloudComputeV1.Operation().with {
      $0.error = GoogleCloudComputeV1.Operation.Error().with {
        $0.errors = [GoogleCloudComputeV1.Operation.Error.Errors().with { $0.message = "fail" }]
      }
    }
    #expect(throws: RequestError.self) {
      try operation._detectErrors()
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
    #expect(throws: RequestError.self) {
      try operation._detectErrors()
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
    #expect(throws: RequestError.self) {
      try operation._detectErrors()
    }
  }
}
