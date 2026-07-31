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

@testable import GoogleCloudGax

@Suite struct PaginatedResponseTest {
  struct Item: Codable, Equatable { var name: String }

  struct ListItemsRequest {
    public var pageToken: String
    public init(pageToken: String = String()) { self.pageToken = pageToken }
  }

  struct ListItemsResponse: _PaginatedResponse {
    public var items: [Item]
    public var nextPageToken: String
    public init(
      items: [Item],
      nextPageToken: String,
    ) {
      self.items = items
      self.nextPageToken = nextPageToken
    }

    public func _getPaginatedItems() -> [Item] {
      return self.items
    }
    public func _nextPageToken() -> String {
      return self.nextPageToken
    }
  }

  class PaginatedService {
    public var mockResponses: [ListItemsResponse] = []
    init(mockResponses: [ListItemsResponse]) {
      self.mockResponses = mockResponses
    }
    public func listItems(request: ListItemsRequest) async throws -> ListItemsResponse {
      if mockResponses.isEmpty {
        throw NSError(domain: "no responses", code: 0)
      }
      let response = mockResponses.removeFirst()
      return response
    }
    public func listItems(byItem: ListItemsRequest) -> PaginatedResponseSequence<
      Item, ListItemsResponse
    > {
      let listRpc = { (token: String) async throws -> ListItemsResponse in
        var request = byItem
        request.pageToken = token
        return try await self.listItems(request: request)
      }
      return PaginatedResponseSequence(listRpc: listRpc)
    }
  }

  @Test func onePage() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [Item(name: "item1"), Item(name: "item2")], nextPageToken: "")
      ])
    var array: [Item] = []
    for try await item in service.listItems(
      byItem: .init()
    ) {
      array.append(item)
    }
    #expect(array == [Item(name: "item1"), Item(name: "item2")])
  }

  @Test func multiplePages() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [Item(name: "item1"), Item(name: "item2")], nextPageToken: "abc"),
        ListItemsResponse(items: [Item(name: "item3"), Item(name: "item4")], nextPageToken: "def"),
        ListItemsResponse(items: [Item(name: "item5"), Item(name: "item6")], nextPageToken: ""),
      ])
    var array: [Item] = []
    for try await item in service.listItems(
      byItem: .init()
    ) {
      array.append(item)
    }
    #expect(
      array == [
        Item(name: "item1"), Item(name: "item2"), Item(name: "item3"), Item(name: "item4"),
        Item(name: "item5"), Item(name: "item6"),
      ])
  }

  @Test func noResults() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [], nextPageToken: "")
      ])
    var array: [Item] = []
    for try await item in service.listItems(
      byItem: .init()
    ) {
      array.append(item)
    }
    #expect(array.isEmpty)
  }
}
