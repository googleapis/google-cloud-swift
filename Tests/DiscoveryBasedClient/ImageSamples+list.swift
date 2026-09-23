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

// [START compute_images_list]
import GoogleCloudComputeV1
import Logging

extension ImageSamples {
  static public func list(
    client: ImagesClient, projectId: String, logger: Logger
  ) async throws {
    logger.info("Calling listImages()")
    let images = client.list(
      byItem: .init().with {
        $0.project = projectId
      })
    for try await image in images {
      logger.info("  image = \(image)")
    }
    logger.info("listImages() completed successfully")
  }
}
// [END compute_images_list]
