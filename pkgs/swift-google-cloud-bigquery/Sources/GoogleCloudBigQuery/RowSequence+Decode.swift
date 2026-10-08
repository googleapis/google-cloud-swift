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

extension RowSequence {
  /// The rows decoded into a `Decodable` type, fetched lazily like the rows themselves.
  ///
  /// ```swift
  /// struct Person: Decodable { var name: String; var age: Int64? }
  /// for try await person in result.rows.decode(Person.self) {
  ///   print(person.name)
  /// }
  /// ```
  ///
  /// Each row is decoded with ``Row/decode(_:)``. Iteration throws the first `DecodingError`.
  public func decode<T: Decodable>(_ type: T.Type = T.self) -> some AsyncSequence<T, any Error> {
    DecodedRowSequence<T>(rows: self)
  }
}

/// The rows of a ``RowSequence`` decoded into `T`.
///
/// A dedicated sequence rather than `map`, so that no closure captures the metatype of `T`,
/// which need not be `Sendable`.
struct DecodedRowSequence<T: Decodable>: AsyncSequence {
  let rows: RowSequence

  func makeAsyncIterator() -> Iterator {
    Iterator(rows: self.rows.makeAsyncIterator())
  }

  struct Iterator: AsyncIteratorProtocol {
    var rows: RowSequence.AsyncIterator

    mutating func next() async throws -> T? {
      guard let row = try await self.rows.next() else { return nil }
      return try row.decode(T.self)
    }
  }
}
