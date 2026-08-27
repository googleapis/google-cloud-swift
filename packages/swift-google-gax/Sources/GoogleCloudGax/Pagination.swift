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
public protocol _PaginatedResponse<Item> {
  associatedtype Item

  func _nextPageToken() -> String

  func _getPaginatedItems() -> [Item]
}

/// A sequence that manages cursor-based pagination automatically.
public final class PaginatedResponseSequence<Item, ResponseType: _PaginatedResponse<Item>>:
  AsyncSequence
{
  public typealias Element = Item
  public typealias ListRpc = (String) async throws -> ResponseType

  private let listRpc: ListRpc

  // Creates a new paginated response sequence.
  public init(listRpc: @escaping ListRpc) {
    self.listRpc = listRpc
  }

  public func makeAsyncIterator() -> _ItemIterator {
    _ItemIterator(listRpc: listRpc)
  }

  public final class _ItemIterator: AsyncIteratorProtocol {
    private let listRpc: ListRpc
    private var buffer: [Item] = []
    private var nextToken: String = String()
    private var hasReachedEnd = false

    init(listRpc: @escaping ListRpc) {
      self.listRpc = listRpc
    }

    public func next() async throws -> Item? {
      // 1. If we have cached items, serve them first.
      if !buffer.isEmpty {
        return buffer.removeFirst()
      }

      // 2. Stop if we've previously determined there's no more data.
      guard !hasReachedEnd else { return nil }

      // 3. Fetch the next page using the page token from the previous response.
      let response = try await listRpc(nextToken)
      buffer = response._getPaginatedItems()

      // 4. Update the token. If there is no next token, remember that we
      // don't need to fetch any more pages.
      nextToken = response._nextPageToken()
      if nextToken.isEmpty {
        hasReachedEnd = true
      }

      // 5. If the fetch returned nothing, we are done.
      if buffer.isEmpty {
        hasReachedEnd = true
        return nil
      }

      return buffer.removeFirst()
    }
  }
}
