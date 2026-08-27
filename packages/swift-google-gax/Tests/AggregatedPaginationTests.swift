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
import Testing
import GoogleRpc
import GoogleCloudGax

@Suite struct AggregatedPaginatedResponseTest {
  public struct Item: Codable, Equatable { var name: String }

  struct Request {
    public var pageToken: String
    public init(pageToken: String = String()) { self.pageToken = pageToken }
  }

  struct Response: _PaginatedResponse {
    public var items: [String: Item]
    public var nextPageToken: String?
    public init(
      items: [String: Item],
      nextPageToken: String?,
    ) {
      self.items = items
      self.nextPageToken = nextPageToken
    }

    public func _nextPageToken() -> String {
      return nextPageToken ?? ""
    }
    public func _getPaginatedItems() -> [(String, Item)] {
      return items.map { ($0, $1) }
    }
  }

  class Service {
    public var mockResponses: [Response] = []

    public init(_ responses: [Response]) {
      self.mockResponses = responses
    }

    public func aggregatedListItems(request: Request) async throws
      -> Response
    {
      if mockResponses.isEmpty {
        throw GoogleCloudGax.RequestError.service(
          ServiceError.init(code: GoogleRpc.Code.invalidArgument, message: "no more mocks"))
      }
      return mockResponses.removeFirst()
    }
    public func aggregatedListItems(byItem: Request) -> PaginatedResponseSequence<
      (String, Item), Response
    > {
      let listRpc = { (token: String) async throws -> Response in
        var request = byItem
        request.pageToken = token
        return try await self.aggregatedListItems(request: request)
      }
      return PaginatedResponseSequence(listRpc: listRpc)
    }
  }

  @Test func emptyAggregatedList() async throws {
    let service = Service([Response(items: [:], nextPageToken: nil)])
    let got = try await aggregateAll(service)
    #expect(got == [:])
  }

  @Test func onePageAggregatedList() async throws {
    let service = Service([
      Response(items: ["group1": Item(name: "item1")], nextPageToken: nil)
    ])
    let got = try await aggregateAll(service)
    #expect(got == ["group1": Item(name: "item1")])
  }

  @Test func multiplePagesAggregatedList() async throws {
    let service = Service([
      Response(
        items: [
          "group1": Item(name: "item1"),
          "group2": Item(name: "item2"),
        ], nextPageToken: "p1"),
      Response(
        items: [
          "group3": Item(name: "item3")
        ], nextPageToken: nil),
    ])
    let got = try await aggregateAll(service)
    #expect(
      got == [
        "group1": Item(name: "item1"),
        "group2": Item(name: "item2"),
        "group3": Item(name: "item3"),
      ])
  }

  func aggregateAll(_ service: Service) async throws -> [String: Item] {
    var result: [String: Item] = [:]
    for try await (group, item) in service.aggregatedListItems(
      byItem: .init()
    ) {
      result[group] = item
    }
    return result
  }
}
