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

@_spi(GoogleCloudInternal) @testable import GoogleGax

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

  final class PaginatedService: PaginatedServiceProtocol, @unchecked Sendable {
    public var mockResponses: [ListItemsResponse] = []
    public var requestedTokens: [String] = []
    init(mockResponses: [ListItemsResponse]) {
      self.mockResponses = mockResponses
    }
    public func listItems(request: ListItemsRequest) async throws -> ListItemsResponse {
      requestedTokens.append(request.pageToken)
      if mockResponses.isEmpty {
        throw NSError(domain: "no responses", code: 0)
      }
      let response = mockResponses.removeFirst()
      return response
    }
  }

  @Test func onePage() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [Item(name: "item1"), Item(name: "item2")], nextPageToken: "")
      ])
    var array: [Item] = []
    for try await item in service.listItemsByItems(
      request: .init()
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
    for try await item in service.listItemsByItems(
      request: .init()
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
    for try await item in service.listItemsByItems(
      request: .init()
    ) {
      array.append(item)
    }
    #expect(array.isEmpty)
  }

  @Test func emptyIntermediatePage() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [Item(name: "item1"), Item(name: "item2")], nextPageToken: "abc"),
        ListItemsResponse(items: [], nextPageToken: "def"),
        ListItemsResponse(items: [Item(name: "item3"), Item(name: "item4")], nextPageToken: ""),
      ])
    var array: [Item] = []
    for try await item in service.listItemsByItems(
      request: .init()
    ) {
      array.append(item)
    }
    #expect(
      array == [
        Item(name: "item1"), Item(name: "item2"), Item(name: "item3"), Item(name: "item4"),
      ])
  }

  @Test func emptyInitialPage() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [], nextPageToken: "abc"),
        ListItemsResponse(items: [Item(name: "item1"), Item(name: "item2")], nextPageToken: ""),
      ])
    var array: [Item] = []
    for try await item in service.listItemsByItems(
      request: .init()
    ) {
      array.append(item)
    }
    #expect(array == [Item(name: "item1"), Item(name: "item2")])
  }

  @Test func multipleConsecutiveEmptyPages() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [Item(name: "item1")], nextPageToken: "p1"),
        ListItemsResponse(items: [], nextPageToken: "p2"),
        ListItemsResponse(items: [], nextPageToken: "p3"),
        ListItemsResponse(items: [Item(name: "item2")], nextPageToken: ""),
      ])
    var array: [Item] = []
    for try await item in service.listItemsByItems(
      request: .init()
    ) {
      array.append(item)
    }
    #expect(array == [Item(name: "item1"), Item(name: "item2")])
  }

  @Test func emptyPagesEndingInEmptyPage() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [], nextPageToken: "p1"),
        ListItemsResponse(items: [], nextPageToken: "p2"),
        ListItemsResponse(items: [], nextPageToken: ""),
      ])
    var array: [Item] = []
    for try await item in service.listItemsByItems(
      request: .init()
    ) {
      array.append(item)
    }
    #expect(array.isEmpty)
  }

  actor ItemCollector {
    private(set) var items: [Item] = []
    func record(_ item: Item) {
      items.append(item)
    }
  }

  @MainActor
  final class ViewModel {
    private let service: any PaginatedServiceProtocol
    let collector = ItemCollector()

    init(service: any PaginatedServiceProtocol) {
      self.service = service
    }

    func startBackgroundStream() -> Task<[Item], Swift.Error> {
      // Construct the paginated sequence on @MainActor from the service protocol existential
      // and send it across isolation boundaries into a detached background worker.
      let sequence = service.listItemsByItems(request: .init())
      let collector = self.collector
      return Task.detached {
        for try await item in sequence {
          await collector.record(item)
        }
        return await collector.items
      }
    }
  }

  @Test func streamPaginatedSequenceAcrossMainActorAndDetachedTask() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [Item(name: "item1"), Item(name: "item2")], nextPageToken: "p2"),
        ListItemsResponse(items: [Item(name: "item3")], nextPageToken: ""),
      ])
    let viewModel = await ViewModel(service: service)
    let task = await viewModel.startBackgroundStream()
    let collected = try await task.value
    #expect(collected == [Item(name: "item1"), Item(name: "item2"), Item(name: "item3")])
  }

  @Test func independentConcurrentIterationsOverSameSequence() async throws {
    // Because PaginatedResponseSequence is a Sendable struct, passing the same sequence
    // to multiple concurrent tasks gives each task its own independent iterator state.
    let sequence = PaginatedResponseSequence<Item, ListItemsResponse> { token in
      if token.isEmpty {
        return ListItemsResponse(items: [Item(name: "a"), Item(name: "b")], nextPageToken: "p2")
      }
      return ListItemsResponse(items: [Item(name: "c")], nextPageToken: "")
    }

    let results = try await withThrowingTaskGroup(of: [Item].self) { group in
      for _ in 0..<2 {
        group.addTask {
          var items: [Item] = []
          for try await item in sequence {
            items.append(item)
          }
          return items
        }
      }
      var allRuns: [[Item]] = []
      for try await run in group {
        allRuns.append(run)
      }
      return allRuns
    }

    #expect(results.count == 2)
    #expect(results[0] == [Item(name: "a"), Item(name: "b"), Item(name: "c")])
    #expect(results[1] == [Item(name: "a"), Item(name: "b"), Item(name: "c")])
  }

  @Test func asyncSequenceCombinators() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(
          items: [Item(name: "item1"), Item(name: "item2")], nextPageToken: "token1"),
        ListItemsResponse(items: [Item(name: "item3"), Item(name: "item4")], nextPageToken: ""),
      ])

    var prefixed: [Item] = []
    for try await item in service.listItemsByItems(request: .init()).prefix(3) {
      prefixed.append(item)
    }
    #expect(prefixed == [Item(name: "item1"), Item(name: "item2"), Item(name: "item3")])

    let service2 = PaginatedService(
      mockResponses: [
        ListItemsResponse(
          items: [Item(name: "a"), Item(name: "b"), Item(name: "c")], nextPageToken: "")
      ])
    var filteredAndMapped: [String] = []
    for try await name in service2.listItemsByItems(request: .init()).filter({ $0.name != "b" })
      .map({
        $0.name.uppercased()
      })
    {
      filteredAndMapped.append(name)
    }
    #expect(filteredAndMapped == ["A", "C"])
  }

  @Test func initialPageToken() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(
          items: [Item(name: "item3"), Item(name: "item4")], nextPageToken: "token3"),
        ListItemsResponse(items: [Item(name: "item5")], nextPageToken: ""),
      ])
    var array: [Item] = []
    for try await item in service.listItemsByItems(
      request: .init(pageToken: "token2")
    ) {
      array.append(item)
    }
    #expect(array == [Item(name: "item3"), Item(name: "item4"), Item(name: "item5")])
    #expect(service.requestedTokens == ["token2", "token3"])

    let optionalToken: String? = nil
    let nilTokenSequence = PaginatedResponseSequence<Item, ListItemsResponse>(
      listRpc: { _ in
        ListItemsResponse(items: [Item(name: "item1")], nextPageToken: "")
      },
      initialPageToken: optionalToken
    )
    var nilTokenItems: [Item] = []
    for try await item in nilTokenSequence {
      nilTokenItems.append(item)
    }
    #expect(nilTokenItems == [Item(name: "item1")])
  }

  @Test func resumptionTokenOnFailure() async throws {
    let sequence = PaginatedResponseSequence<Item, ListItemsResponse>(
      listRpc: { token in
        if token.isEmpty {
          return ListItemsResponse(
            items: [Item(name: "page1_item")], nextPageToken: "page2_token")
        }
        throw NSError(domain: "network_failure", code: 500)
      }
    )

    var iterator = sequence.makeAsyncIterator()
    #expect(iterator.nextPageToken == "")

    let item1 = try await iterator.next()
    #expect(item1 == Item(name: "page1_item"))
    #expect(iterator.nextPageToken == "page2_token")

    do {
      _ = try await iterator.next()
      Issue.record("Expected error")
    } catch {
      // The iterator should preserve the page token that was attempted and failed
      #expect(iterator.nextPageToken == "page2_token")
    }

    // Now resume from the saved token
    let resumedSequence = PaginatedResponseSequence<Item, ListItemsResponse>(
      listRpc: { token in
        #expect(token == "page2_token")
        return ListItemsResponse(items: [Item(name: "page2_item")], nextPageToken: "")
      },
      initialPageToken: iterator.nextPageToken
    )
    var resumedItems: [Item] = []
    for try await item in resumedSequence {
      resumedItems.append(item)
    }
    #expect(resumedItems == [Item(name: "page2_item")])
  }

  @Test func pageSequence() async throws {
    let service = PaginatedService(
      mockResponses: [
        ListItemsResponse(items: [Item(name: "item1"), Item(name: "item2")], nextPageToken: "p2"),
        ListItemsResponse(items: [], nextPageToken: "p3"),
        ListItemsResponse(items: [Item(name: "item3")], nextPageToken: ""),
      ])

    let seq = service.listItemsSequence(request: .init(pageToken: "p1"))
    var pageCount = 0
    var allItems: [Item] = []
    for try await page in seq.pages {
      pageCount += 1
      allItems.append(contentsOf: page.items)
    }
    #expect(pageCount == 3)
    #expect(allItems == [Item(name: "item1"), Item(name: "item2"), Item(name: "item3")])
    #expect(service.requestedTokens == ["p1", "p2", "p3"])
  }

  @Test func pageSequenceResumption() async throws {
    let sequence = PaginatedResponseSequence<Item, ListItemsResponse>(
      listRpc: { token in
        if token == "p1" {
          return ListItemsResponse(items: [Item(name: "i1")], nextPageToken: "p2")
        }
        throw NSError(domain: "page_fetch_failed", code: 503)
      },
      initialPageToken: "p1"
    )

    var pageIterator = sequence.pages.makeAsyncIterator()
    #expect(pageIterator.nextPageToken == "p1")

    let page1 = try await pageIterator.next()
    #expect(page1?.items == [Item(name: "i1")])
    #expect(pageIterator.nextPageToken == "p2")

    do {
      _ = try await pageIterator.next()
      Issue.record("Expected error")
    } catch {
      #expect(pageIterator.nextPageToken == "p2")
    }
  }
}

protocol PaginatedServiceProtocol: Sendable {
  func listItems(request: PaginatedResponseTest.ListItemsRequest) async throws
    -> PaginatedResponseTest.ListItemsResponse
}

extension PaginatedServiceProtocol {
  func listItemsByItems(request: PaginatedResponseTest.ListItemsRequest)
    -> some AsyncSequence<PaginatedResponseTest.Item, Swift.Error> & Sendable
  {
    let listRpc = {
      @Sendable (token: String) async throws -> PaginatedResponseTest.ListItemsResponse in
      var request = request
      request.pageToken = token
      return try await self.listItems(request: request)
    }
    return GoogleGax.PaginatedResponseSequence(
      listRpc: listRpc, initialPageToken: request.pageToken)
  }

  func listItemsSequence(request: PaginatedResponseTest.ListItemsRequest)
    -> GoogleGax.PaginatedResponseSequence<
      PaginatedResponseTest.Item, PaginatedResponseTest.ListItemsResponse
    >
  {
    let listRpc = {
      @Sendable (token: String) async throws -> PaginatedResponseTest.ListItemsResponse in
      var request = request
      request.pageToken = token
      return try await self.listItems(request: request)
    }
    return GoogleGax.PaginatedResponseSequence(
      listRpc: listRpc, initialPageToken: request.pageToken)
  }
}
