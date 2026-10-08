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

public import Foundation

/// An IAM policy for a table or view.
///
/// Read a policy with ``BigQueryClient/getIAMPolicy(for:requestedPolicyVersion:options:)``,
/// modify it, and write it back with ``BigQueryClient/setIAMPolicy(_:for:options:)``. Keep the
/// ``etag`` from the read so that a concurrent change is detected instead of overwritten.
public struct IAMPolicy: Sendable, Hashable {
  /// Binds a role to a list of principals, optionally under a condition.
  public struct Binding: Sendable, Hashable {
    /// The role, for example `roles/bigquery.dataViewer`.
    public var role: String

    /// The principals, for example `user:alice@example.com` or `group:team@example.com`.
    public var members: [String]

    /// The condition under which the binding applies, or `nil` for an unconditional binding.
    public var condition: Expr?

    /// Creates a binding.
    public init(role: String, members: [String], condition: Expr? = nil) {
      self.role = role
      self.members = members
      self.condition = condition
    }
  }

  /// The policy format version (1, 2, or 3), or `nil` if the server did not report one.
  ///
  /// Policies with conditional bindings require version 3.
  public var version: Int32?

  /// The role bindings.
  public var bindings: [Binding]

  /// The policy version tag used for optimistic concurrency, or `nil` for a new policy.
  public var etag: Data?

  /// Creates a policy.
  public init(version: Int32? = nil, bindings: [Binding] = [], etag: Data? = nil) {
    self.version = version
    self.bindings = bindings
    self.etag = etag
  }
}

/// A [Common Expression Language] expression, used for IAM conditions and conditional dataset
/// access entries.
///
/// [Common Expression Language]: https://github.com/google/cel-spec
public struct Expr: Sendable, Hashable {
  /// The expression text, for example `request.time < timestamp('2030-01-01T00:00:00Z')`.
  public var expression: String

  /// A short title for the expression.
  public var title: String?

  /// A longer description of the expression.
  public var description: String?

  /// The file name and position for error reporting.
  public var location: String?

  /// Creates an expression.
  public init(
    _ expression: String, title: String? = nil, description: String? = nil,
    location: String? = nil
  ) {
    self.expression = expression
    self.title = title
    self.description = description
    self.location = location
  }
}
