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
  let handle1 = try await publisher.startPublish(
    Message(data: Data("first".utf8)), options: PublishOptions())
  let handle2 = try await publisher.startPublish(
    Message(data: Data("second".utf8)), options: PublishOptions())
  let ids = try await (handle1.result().messageID, handle2.result().messageID)
  print("Published IDs: \(ids.0), \(ids.1)")
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
