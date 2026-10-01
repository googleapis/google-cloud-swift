// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// For internal use only. This protocol identifies response messages that adhere to the
/// [AIP-158 pagination](https://google.aip.dev/158) standard.
@_spi(GoogleCloudInternal)
public protocol _PaginatedResponse<Item>: Sendable {
  associatedtype Item

  func _nextPageToken() -> String

  func _getPaginatedItems() -> [Item]
}

/// A sequence that manages cursor-based pagination automatically.
@_spi(GoogleCloudInternal)
public struct PaginatedResponseSequence<Item, ResponseType>:
  AsyncSequence, Sendable
{
  public typealias Element = Item
  public typealias ListRpc = @Sendable (String) async throws -> ResponseType

  private let initialPageToken: String
  private let fetchPage:
    @Sendable (String) async throws -> (response: ResponseType, items: [Item], nextToken: String)

  /// Creates a new paginated response sequence.
  public init(
    listRpc: @escaping ListRpc,
    initialPageToken: String? = nil
  ) where ResponseType: _PaginatedResponse<Item> {
    self.initialPageToken = initialPageToken ?? ""
    self.fetchPage = { token in
      let response = try await listRpc(token)
      return (response, response._getPaginatedItems(), response._nextPageToken())
    }
  }

  /// An `AsyncSequence` that yields each response page instead of individual items.
  public var pages: PageSequence {
    PageSequence(fetchPage: fetchPage, initialPageToken: initialPageToken)
  }

  public func makeAsyncIterator() -> _ItemIterator {
    _ItemIterator(fetchPage: fetchPage, initialPageToken: initialPageToken)
  }

  public struct _ItemIterator: AsyncIteratorProtocol {
    private let fetchPage:
      @Sendable (String) async throws -> (response: ResponseType, items: [Item], nextToken: String)
    private var buffer: ArraySlice<Item> = []
    private var hasReachedEnd = false

    /// The page token for the next page to fetch. Callers can inspect this token if iteration
    /// halts or throws to resume iteration on a subsequent request.
    public private(set) var nextPageToken: String

    init(
      fetchPage:
        @escaping @Sendable (String) async throws -> (
          response: ResponseType, items: [Item], nextToken: String
        ),
      initialPageToken: String = ""
    ) {
      self.fetchPage = fetchPage
      self.nextPageToken = initialPageToken
    }

    public mutating func next() async throws -> Item? {
      // Continue fetching pages until we have items to return or there are no more pages.
      // According to AIP-158, intermediate pages may be empty while still returning a next page token.
      while buffer.isEmpty && !hasReachedEnd {
        let page = try await fetchPage(nextPageToken)
        buffer = ArraySlice(page.items)
        nextPageToken = page.nextToken
        if nextPageToken.isEmpty {
          hasReachedEnd = true
        }
      }

      return buffer.popFirst()
    }
  }

  /// A sequence that yields whole response pages.
  public struct PageSequence: AsyncSequence, Sendable {
    public typealias Element = ResponseType

    private let fetchPage:
      @Sendable (String) async throws -> (response: ResponseType, items: [Item], nextToken: String)
    private let initialPageToken: String

    init(
      fetchPage:
        @escaping @Sendable (String) async throws -> (
          response: ResponseType, items: [Item], nextToken: String
        ),
      initialPageToken: String = ""
    ) {
      self.fetchPage = fetchPage
      self.initialPageToken = initialPageToken
    }

    public func makeAsyncIterator() -> _PageIterator {
      _PageIterator(fetchPage: fetchPage, initialPageToken: initialPageToken)
    }

    public struct _PageIterator: AsyncIteratorProtocol {
      private let fetchPage:
        @Sendable (String) async throws -> (
          response: ResponseType, items: [Item], nextToken: String
        )
      private var hasReachedEnd = false

      /// The page token for the next page to fetch. Callers can inspect this token if iteration
      /// halts or throws to resume iteration on a subsequent request.
      public private(set) var nextPageToken: String

      init(
        fetchPage:
          @escaping @Sendable (String) async throws -> (
            response: ResponseType, items: [Item], nextToken: String
          ),
        initialPageToken: String = ""
      ) {
        self.fetchPage = fetchPage
        self.nextPageToken = initialPageToken
      }

      public mutating func next() async throws -> ResponseType? {
        guard !hasReachedEnd else {
          return nil
        }

        let page = try await fetchPage(nextPageToken)
        nextPageToken = page.nextToken
        if nextPageToken.isEmpty {
          hasReachedEnd = true
        }
        return page.response
      }
    }
  }
}
