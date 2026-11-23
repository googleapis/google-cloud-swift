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
import GoogleCloudPubSub
import GoogleCloudPubSubV1
import PubSubSamples
import Testing

@Suite struct PubSubSamplesDriver {
  @Test(.enabled(if: Self.enabled())) func runCoreSamples() async throws {
    let projectID = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]!
    let serviceAccount =
      ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_SERVICE_ACCOUNT"]
      ?? "swift-sdk-test@\(projectID).iam.gserviceaccount.com"

    let topicAdmin = try TopicAdminClient()
    let subscriptionAdmin = try SubscriptionAdminClient()
    let schemaClient = try SchemaServiceClient()
    let publisherClient = try PublisherClient(
      PublisherClientOptions().with {
        $0.projectID = projectID
      }
    )
    let subscriberClient = try SubscriberClient(
      SubscriberClientOptions().with {
        $0.projectID = projectID
      }
    )

    var cleanupBag = PubSubSampleCleanupBag()
    do {
      try await PubSubSamples.runPubSubCoreSamples(
        topicAdmin: topicAdmin,
        subscriptionAdmin: subscriptionAdmin,
        publisherClient: publisherClient,
        subscriberClient: subscriberClient,
        projectID: projectID,
        serviceAccount: serviceAccount,
        cleanupBag: &cleanupBag
      )
      _ = try await publisherClient.shutdown()
      await PubSubSamples.cleanupPubSubSampleResources(
        topicAdmin: topicAdmin,
        subscriptionAdmin: subscriptionAdmin,
        schemaClient: schemaClient,
        bag: cleanupBag
      )
    } catch {
      _ = try? await publisherClient.shutdown()
      await PubSubSamples.cleanupPubSubSampleResources(
        topicAdmin: topicAdmin,
        subscriptionAdmin: subscriptionAdmin,
        schemaClient: schemaClient,
        bag: cleanupBag
      )
      throw error
    }
  }

  @Test(.enabled(if: Self.enabled())) func runSchemaSamples() async throws {
    let projectID = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]!
    let topicAdmin = try TopicAdminClient()
    let subscriptionAdmin = try SubscriptionAdminClient()
    let schemaClient = try SchemaServiceClient()

    var cleanupBag = PubSubSampleCleanupBag()
    do {
      try await PubSubSamples.runPubSubSchemaSamples(
        schemaClient: schemaClient,
        topicAdmin: topicAdmin,
        projectID: projectID,
        cleanupBag: &cleanupBag
      )
      await PubSubSamples.cleanupPubSubSampleResources(
        topicAdmin: topicAdmin,
        subscriptionAdmin: subscriptionAdmin,
        schemaClient: schemaClient,
        bag: cleanupBag
      )
    } catch {
      await PubSubSamples.cleanupPubSubSampleResources(
        topicAdmin: topicAdmin,
        subscriptionAdmin: subscriptionAdmin,
        schemaClient: schemaClient,
        bag: cleanupBag
      )
      throw error
    }
  }

  static func enabled() -> Bool {
    ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil
      && ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_ENABLE_FLAKES"] == "true"
  }
}
