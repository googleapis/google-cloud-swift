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

// [START compute_instances_delete]
import GoogleCloudComputeV1
import GoogleGax
import Logging

extension InstanceSamples {
  static public func delete(
    client: InstancesClient,
    projectId: String,
    zoneId: String,
    name: String,
    logger: Logger
  ) async throws {
    logger.info("Calling Instances::delete()")
    let operation = try await client.deletePollingUntilDone(
      request: .init().with {
        $0.project = projectId
        $0.zone = zoneId
        $0.instance = name
      }, options: .init())
    logger.info("Instances::list() - response=\(operation)")
  }
}
// [END compute_instances_delete]
