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

import GoogleCloudPubSubV1
import GoogleIAMV1

// [START pubsub_get_topic_policy]
public func getTopicPolicy(
  client: any GoogleCloudPubSubV1.Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String
) async throws -> GoogleIAMV1.Policy {
  let policy = try await client.getIamPolicy(
    request: GoogleIAMV1.GetIamPolicyRequest().with {
      $0.resource = "projects/\(projectID)/topics/\(topicID)"
    }
  )
  print("Topic policy bindings: \(policy.bindings)")
  return policy
}
// [END pubsub_get_topic_policy]

// [START pubsub_set_topic_policy]
public func setTopicPolicy(
  client: any GoogleCloudPubSubV1.Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String,
  role: String,
  member: String
) async throws -> GoogleIAMV1.Policy {
  let resource = "projects/\(projectID)/topics/\(topicID)"
  var policy = try await client.getIamPolicy(
    request: GoogleIAMV1.GetIamPolicyRequest().with {
      $0.resource = resource
    }
  )
  let binding = GoogleIAMV1.Binding().with {
    $0.role = role
    $0.members = [member]
  }
  policy.bindings.append(binding)
  let updated = try await client.setIamPolicy(
    request: GoogleIAMV1.SetIamPolicyRequest().with {
      $0.resource = resource
      $0.policy = policy
    }
  )
  print("Updated topic IAM policy: \(updated.bindings)")
  return updated
}
// [END pubsub_set_topic_policy]

// [START pubsub_test_topic_permissions]
public func testTopicPermissions(
  client: any GoogleCloudPubSubV1.Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String
) async throws -> [String] {
  let response = try await client.testIamPermissions(
    request: GoogleIAMV1.TestIamPermissionsRequest().with {
      $0.resource = "projects/\(projectID)/topics/\(topicID)"
      $0.permissions = [
        "pubsub.topics.attachSubscription",
        "pubsub.topics.publish",
        "pubsub.topics.update",
      ]
    }
  )
  print("Permitted topic permissions: \(response.permissions)")
  return response.permissions
}
// [END pubsub_test_topic_permissions]

// [START pubsub_get_subscription_policy]
public func getSubscriptionPolicy(
  client: any GoogleCloudPubSubV1.Clients.SubscriptionAdminProtocol,
  projectID: String,
  subscriptionID: String
) async throws -> GoogleIAMV1.Policy {
  let policy = try await client.getIamPolicy(
    request: GoogleIAMV1.GetIamPolicyRequest().with {
      $0.resource = "projects/\(projectID)/subscriptions/\(subscriptionID)"
    }
  )
  print("Subscription policy bindings: \(policy.bindings)")
  return policy
}
// [END pubsub_get_subscription_policy]

// [START pubsub_set_subscription_policy]
public func setSubscriptionPolicy(
  client: any GoogleCloudPubSubV1.Clients.SubscriptionAdminProtocol,
  projectID: String,
  subscriptionID: String,
  role: String,
  member: String
) async throws -> GoogleIAMV1.Policy {
  let resource = "projects/\(projectID)/subscriptions/\(subscriptionID)"
  var policy = try await client.getIamPolicy(
    request: GoogleIAMV1.GetIamPolicyRequest().with {
      $0.resource = resource
    }
  )
  let binding = GoogleIAMV1.Binding().with {
    $0.role = role
    $0.members = [member]
  }
  policy.bindings.append(binding)
  let updated = try await client.setIamPolicy(
    request: GoogleIAMV1.SetIamPolicyRequest().with {
      $0.resource = resource
      $0.policy = policy
    }
  )
  print("Updated subscription IAM policy: \(updated.bindings)")
  return updated
}
// [END pubsub_set_subscription_policy]

// [START pubsub_test_subscription_permissions]
public func testSubscriptionPermissions(
  client: any GoogleCloudPubSubV1.Clients.SubscriptionAdminProtocol,
  projectID: String,
  subscriptionID: String
) async throws -> [String] {
  let response = try await client.testIamPermissions(
    request: GoogleIAMV1.TestIamPermissionsRequest().with {
      $0.resource = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.permissions = [
        "pubsub.subscriptions.consume",
        "pubsub.subscriptions.update",
      ]
    }
  )
  print("Permitted subscription permissions: \(response.permissions)")
  return response.permissions
}
// [END pubsub_test_subscription_permissions]
