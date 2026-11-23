// snippet.hide
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

// snippet.show
import Foundation
import GoogleCloudPubSub

func sample(subscription: String) async throws {
  let subscriber = try SubscriberClient()
  let stream = try subscriber.subscribe(
    subscription: subscription,
    options: SubscribeOptions()
  )
  for try await received in stream {
    let payload = String(decoding: received.message.data, as: UTF8.self)
    print("Received \(received.message.messageID): \(payload)")
    received.ack()
    break
  }
  _ = try await stream.stop(
    options: SubscriberShutdownOptions().with {
      $0.behavior = .waitForProcessing
    })
}
// snippet.hide

@main
struct SnippetRunner {
  static func main() async {
    do {
      try await sample(subscription: "projects/my-project/subscriptions/my-sub")
    } catch {
      print("Error: \(error)")
    }
  }
}
