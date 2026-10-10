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

/// One page of results from a list operation.
public struct Page<Element: Sendable>: Sendable {
  /// The items in this page.
  public var items: [Element]

  /// The token for the next page, or `nil` if this is the last page.
  ///
  /// Pass this token to the list operation to resume listing from the next page.
  public var nextPageToken: String?

  /// Creates a page.
  public init(items: [Element], nextPageToken: String? = nil) {
    self.items = items
    self.nextPageToken = nextPageToken
  }
}

/// The items of a paginated list operation, fetched lazily one page at a time.
///
/// ```swift
/// for try await dataset in client.listDatasets() {
///   print(dataset.id)
/// }
/// ```
///
/// Each iteration starts from the first page. Pages are fetched only as the iteration needs them.
/// Use ``pages`` to see page boundaries and tokens.
public struct PagedSequence<Element: Sendable>: AsyncSequence, Sendable {
  /// Fetches the page that starts at `pageToken`, or the first page if `pageToken` is `nil`.
  public typealias Fetch = @Sendable (_ pageToken: String?) async throws -> Page<Element>

  let firstPage: Page<Element>?
  let fetch: Fetch

  /// Creates a sequence that fetches every page, including the first, with `fetch`.
  public init(fetch: @escaping Fetch) {
    self.firstPage = nil
    self.fetch = fetch
  }

  /// Creates a sequence whose first page is already known.
  ///
  /// `fetch` is called only for later pages.
  public init(firstPage: Page<Element>, fetch: @escaping Fetch) {
    self.firstPage = firstPage
    self.fetch = fetch
  }

  /// Creates a sequence over a fixed list of items, for example in tests.
  public init(_ items: [Element]) {
    self.init(firstPage: Page(items: items), fetch: { _ in Page(items: []) })
  }

  /// The pages of this sequence.
  public var pages: Pages {
    Pages(firstPage: self.firstPage, fetch: self.fetch)
  }

  /// Fetches every remaining page and returns all the items.
  public func collect() async throws -> [Element] {
    var items: [Element] = []
    for try await page in self.pages {
      items.append(contentsOf: page.items)
    }
    return items
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(pages: self.pages.makeAsyncIterator())
  }

  /// Iterates over the items of a ``PagedSequence``.
  public struct AsyncIterator: AsyncIteratorProtocol {
    var pages: Pages.AsyncIterator
    var buffer: [Element] = []
    var index = 0

    public mutating func next() async throws -> Element? {
      while self.index >= self.buffer.count {
        self.buffer = []
        guard let page = try await self.pages.next() else { return nil }
        self.buffer = page.items
        self.index = 0
      }
      defer { self.index += 1 }
      return self.buffer[self.index]
    }
  }
}

extension PagedSequence {
  /// The element type of the sequence, named so that nested sequences can refer to it.
  public typealias Item = Element

  /// The pages of a ``PagedSequence``.
  public struct Pages: AsyncSequence, Sendable {
    let firstPage: Page<Item>?
    let fetch: PagedSequence<Item>.Fetch

    public func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(firstPage: self.firstPage, fetch: self.fetch)
    }

    /// Iterates over the pages of a ``PagedSequence``.
    public struct AsyncIterator: AsyncIteratorProtocol {
      enum State {
        case start(Page<Item>?)
        case next(String)
        case done
      }

      let fetch: PagedSequence<Item>.Fetch
      var state: State

      init(firstPage: Page<Item>?, fetch: @escaping PagedSequence<Item>.Fetch) {
        self.fetch = fetch
        self.state = .start(firstPage)
      }

      public mutating func next() async throws -> Page<Item>? {
        let page: Page<Item>
        switch self.state {
        case .done:
          return nil
        case .start(let firstPage):
          self.state = .done
          if let firstPage {
            page = firstPage
          } else {
            page = try await self.fetch(nil)
          }
        case .next(let token):
          page = try await self.fetch(token)
        }
        // Proto3 represents an absent token as the empty string.
        if let token = page.nextPageToken, !token.isEmpty {
          self.state = .next(token)
        } else {
          self.state = .done
        }
        return page
      }
    }
  }
}
