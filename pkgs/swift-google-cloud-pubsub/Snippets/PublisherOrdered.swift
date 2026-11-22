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

func sample(topic: String) async throws {
  let publisher = try Publisher(topic: topic)
  let ordered = Message(data: Data("event-1".utf8), orderingKey: "order-42")
  do {
    let result = try await publisher.publish(ordered)
    print("Published ordered ID: \(result.messageID)")
  } catch {
    _ = try await publisher.resumePublishing(
      orderingKey: "order-42",
      options: ResumePublishingOptions()
    )
    print("Resumed ordering key after error: \(error)")
  }
  _ = try await publisher.shutdown()
}
// snippet.hide

@main
struct SnippetRunner {
  static func main() async {
    do {
      try await sample(topic: "projects/my-project/topics/my-topic")
    } catch {
      print("Error: \(error)")
    }
  }
}
