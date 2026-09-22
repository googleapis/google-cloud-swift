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
public protocol _PaginatedResponse<Item> {
  associatedtype Item

  func _nextPageToken() -> String

  func _getPaginatedItems() -> [Item]
}

/// A sequence that manages cursor-based pagination automatically.
public final class PaginatedResponseSequence<Item, ResponseType>:
  AsyncSequence
{
  public typealias Element = Item
  public typealias ListRpc = (String) async throws -> ResponseType

  private let fetchPage: (String) async throws -> (items: [Item], nextToken: String)

  // Creates a new paginated response sequence.
  @_spi(GoogleCloudInternal)
  public init(listRpc: @escaping ListRpc) where ResponseType: _PaginatedResponse<Item> {
    self.fetchPage = { token in
      let response = try await listRpc(token)
      return (response._getPaginatedItems(), response._nextPageToken())
    }
  }

  public func makeAsyncIterator() -> _ItemIterator {
    _ItemIterator(fetchPage: fetchPage)
  }

  public final class _ItemIterator: AsyncIteratorProtocol {
    private let fetchPage: (String) async throws -> (items: [Item], nextToken: String)
    private var buffer: [Item] = []
    private var nextToken: String = String()
    private var hasReachedEnd = false

    init(fetchPage: @escaping (String) async throws -> (items: [Item], nextToken: String)) {
      self.fetchPage = fetchPage
    }

    public func next() async throws -> Item? {
      // Continue fetching pages until we have items to return or there are no more pages.
      // According to AIP-158, intermediate pages may be empty while still returning a next page token.
      while buffer.isEmpty && !hasReachedEnd {
        let page = try await fetchPage(nextToken)
        buffer = page.items
        nextToken = page.nextToken
        if nextToken.isEmpty {
          hasReachedEnd = true
        }
      }

      guard !buffer.isEmpty else {
        return nil
      }

      return buffer.removeFirst()
    }
  }
}
