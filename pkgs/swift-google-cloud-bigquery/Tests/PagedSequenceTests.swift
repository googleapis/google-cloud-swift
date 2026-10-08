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
import Synchronization
import Testing

@testable import GoogleCloudBigQuery

@Suite struct PagedSequenceTests {
  /// Serves `pages` keyed by token (`nil` is the first page) and records the tokens requested.
  private final class Server: Sendable {
    let pages: [String: Page<Int>]
    let tokens = Mutex<[String?]>([])

    init(_ pages: [String: Page<Int>]) { self.pages = pages }

    func fetch(_ token: String?) -> Page<Int> {
      self.tokens.withLock { $0.append(token) }
      return self.pages[token ?? ""] ?? Page(items: [])
    }
  }

  // Design: §4.4
  @Test func iteratesAllPagesLazily() async throws {
    let server = Server([
      "": Page(items: [1, 2], nextPageToken: "a"),
      "a": Page(items: [3], nextPageToken: "b"),
      "b": Page(items: [4]),
    ])
    let sequence = PagedSequence<Int> { server.fetch($0) }
    #expect(server.tokens.withLock { $0 }.isEmpty)
    var iterator = sequence.makeAsyncIterator()
    #expect(try await iterator.next() == 1)
    #expect(server.tokens.withLock { $0 } == [nil])
    #expect(try await sequence.collect() == [1, 2, 3, 4])
  }

  // Design: §4.4
  @Test func skipsEmptyIntermediatePages() async throws {
    let server = Server([
      "": Page(items: [], nextPageToken: "a"),
      "a": Page(items: [], nextPageToken: "b"),
      "b": Page(items: [7]),
    ])
    #expect(try await PagedSequence<Int> { server.fetch($0) }.collect() == [7])
  }

  // Design: §4.4
  @Test func emptyTokenEndsTheSequence() async throws {
    let server = Server(["": Page(items: [1], nextPageToken: "")])
    #expect(try await PagedSequence<Int> { server.fetch($0) }.collect() == [1])
    #expect(server.tokens.withLock { $0 } == [nil])
  }

  // Design: §4.4
  @Test func firstPageIsNotRefetched() async throws {
    let server = Server(["a": Page(items: [2])])
    let sequence = PagedSequence(firstPage: Page(items: [1], nextPageToken: "a")) {
      server.fetch($0)
    }
    #expect(try await sequence.collect() == [1, 2])
    #expect(server.tokens.withLock { $0 } == ["a"])
  }

  // Design: §4.4
  @Test func pagesExposeTokens() async throws {
    let server = Server(["": Page(items: [1], nextPageToken: "a"), "a": Page(items: [2])])
    var tokens: [String?] = []
    for try await page in PagedSequence<Int>(fetch: { server.fetch($0) }).pages {
      tokens.append(page.nextPageToken)
    }
    #expect(tokens == ["a", nil])
  }

  // Design: §4.4
  @Test func fixedItemsForTestDoubles() async throws {
    #expect(try await PagedSequence([1, 2, 3]).collect() == [1, 2, 3])
    let rows = RowSequence(schema: [Field("x", .int64)], rows: [])
    #expect(try await rows.collect().isEmpty)
    #expect(rows.schema.fields.map(\.name) == ["x"])
  }
}
