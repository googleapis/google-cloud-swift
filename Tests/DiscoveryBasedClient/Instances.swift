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

import GoogleCloudComputeV1
import GoogleCloudTestHelpers
import GoogleCloudGax
import GoogleCloudWKT
import Logging

// Run the samples (which double as naive integration tests).
public enum Instances {
  static public func run(_ logger: Logger) async throws {
    let projectId = try projectId()

    let client = try InstancesClient(ClientOptions().with { $0.logger = logger })
    let name = randomVMId()
    let zone = "us-central1-a"
    try await InstanceSamples.create(
      client: client, projectId: projectId, zoneId: zone, name: name, logger: logger)
    try await InstanceSamples.listAll(
      client: client, projectId: projectId, zoneId: zone, logger: logger)
    try await InstanceSamples.delete(
      client: client, projectId: projectId, zoneId: zone, name: name, logger: logger)
  }
}

enum InstanceSamples {}
