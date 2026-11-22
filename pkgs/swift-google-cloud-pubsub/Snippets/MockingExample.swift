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

enum SampleAppError: Error {
  case failedToProcess
}

final class RecordingAckHandler: AckHandlerProtocol, Sendable {
  func ack(options: AckOptions) -> AckQueuedResult {
    AckQueuedResult()
  }

  func nack(options: NackOptions) -> NackQueuedResult {
    NackQueuedResult()
  }
}

struct MockPublisher: Clients.PublisherProtocol {
  let topic: String

  func startPublish(_ message: Message, options: PublishOptions) async throws -> PublishHandle {
    PublishHandle(resolvedResult: .success(PublishResult(messageID: "mock-id")))
  }
}

func sample() async throws {
  let publisher: any Clients.PublisherProtocol = MockPublisher(topic: "projects/p/topics/t")
  let publishResult = try await publisher.publish(Message(data: Data("hello".utf8)))
  print("Mock published: \(publishResult.messageID)")

  let received = ReceivedMessage(
    message: Message(data: Data("event".utf8)),
    ackHandler: RecordingAckHandler()
  )
  let stream = MessageStream(messages: [received])
  for try await item in stream {
    if item.message.data.isEmpty {
      throw SampleAppError.failedToProcess
    }
    item.ack()
  }
}
// snippet.hide

@main
struct SnippetRunner {
  static func main() async {
    do {
      try await sample()
    } catch {
      print("Error: \(error)")
    }
  }
}
