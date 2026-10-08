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

/// An access control entry of a dataset: grants a role to an entity.
///
/// ```swift
/// var dataset = try await client.getDataset(id)!
/// dataset.access?.append(Acl(.group("analysts@example.com"), role: .reader))
/// dataset = try await client.updateDataset(dataset)
/// ```
///
/// Authorized views, routines, and datasets have no role:
///
/// ```swift
/// Acl(.view(TableID(datasetID: "shared", tableID: "summary")))
/// ```
public struct Acl: Sendable, Hashable {
  /// A dataset access role.
  ///
  /// The service also accepts and returns IAM role names, such as
  /// `roles/bigquery.dataViewer`.
  public struct Role: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The role name as sent to the service.
    public var rawValue: String

    /// Creates a role from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Can read, query, copy, or export tables in the dataset.
    public static let reader = Role(rawValue: "READER")
    /// ``reader`` plus editing or appending data in the dataset.
    public static let writer = Role(rawValue: "WRITER")
    /// ``writer`` plus updating and deleting the dataset.
    public static let owner = Role(rawValue: "OWNER")

    /// The role name.
    public var description: String { self.rawValue }
  }

  /// The kind of resources in an authorized dataset that are granted access.
  public struct TargetType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The target type as sent to the service.
    public var rawValue: String

    /// Creates a target type from its service name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Views in the authorized dataset.
    public static let views = TargetType(rawValue: "VIEWS")
    /// Routines in the authorized dataset.
    public static let routines = TargetType(rawValue: "ROUTINES")

    /// The target type name.
    public var description: String { self.rawValue }
  }

  /// Who or what is granted access.
  ///
  /// Use the static factories to create an entity, and the optional accessors to inspect one.
  /// Exactly one accessor returns a value.
  public struct Entity: Sendable, Hashable {
    enum Value: Sendable, Hashable {
      case user(String)
      case group(String)
      case domain(String)
      case specialGroup(String)
      case iamMember(String)
      case view(TableID)
      case routine(RoutineID)
      case dataset(DatasetID, targetTypes: [TargetType])
      /// An entry whose kind this version of the library does not know.
      case unrecognized
    }

    let value: Value

    init(_ value: Value) {
      self.value = value
    }

    /// A user, by email address.
    public static func user(_ email: String) -> Entity { Entity(.user(email)) }

    /// A Google group, by email address.
    public static func group(_ email: String) -> Entity { Entity(.group(email)) }

    /// Every user in a Google Workspace or Cloud Identity domain, for example `example.com`.
    public static func domain(_ domain: String) -> Entity { Entity(.domain(domain)) }

    /// A special group, such as ``projectOwners`` or ``allAuthenticatedUsers``.
    public static func specialGroup(_ name: String) -> Entity { Entity(.specialGroup(name)) }

    /// Any IAM principal, for example `allUsers` or `serviceAccount:sa@p.iam.gserviceaccount.com`.
    public static func iamMember(_ member: String) -> Entity { Entity(.iamMember(member)) }

    /// An authorized view, which may query the dataset's tables.
    public static func view(_ table: TableID) -> Entity { Entity(.view(table)) }

    /// An authorized routine, which may query the dataset's tables.
    public static func routine(_ routine: RoutineID) -> Entity { Entity(.routine(routine)) }

    /// An authorized dataset, whose resources of the given types may query this dataset.
    public static func dataset(_ dataset: DatasetID, targetTypes: [TargetType]) -> Entity {
      Entity(.dataset(dataset, targetTypes: targetTypes))
    }

    /// The owners of the project that contains the dataset.
    public static let projectOwners = specialGroup("projectOwners")
    /// The readers of the project that contains the dataset.
    public static let projectReaders = specialGroup("projectReaders")
    /// The writers of the project that contains the dataset.
    public static let projectWriters = specialGroup("projectWriters")
    /// Every authenticated user.
    public static let allAuthenticatedUsers = specialGroup("allAuthenticatedUsers")

    /// The user's email address, if the entity is a user.
    public var user: String? {
      if case .user(let email) = self.value { return email }
      return nil
    }

    /// The group's email address, if the entity is a group.
    public var group: String? {
      if case .group(let email) = self.value { return email }
      return nil
    }

    /// The domain, if the entity is a domain.
    public var domain: String? {
      if case .domain(let domain) = self.value { return domain }
      return nil
    }

    /// The special group's name, if the entity is a special group.
    public var specialGroup: String? {
      if case .specialGroup(let name) = self.value { return name }
      return nil
    }

    /// The IAM principal, if the entity is an IAM member.
    public var iamMember: String? {
      if case .iamMember(let member) = self.value { return member }
      return nil
    }

    /// The view, if the entity is an authorized view.
    public var view: TableID? {
      if case .view(let table) = self.value { return table }
      return nil
    }

    /// The routine, if the entity is an authorized routine.
    public var routine: RoutineID? {
      if case .routine(let routine) = self.value { return routine }
      return nil
    }

    /// The dataset, if the entity is an authorized dataset.
    public var dataset: DatasetID? {
      if case .dataset(let dataset, _) = self.value { return dataset }
      return nil
    }

    /// The resource types granted access, if the entity is an authorized dataset.
    public var targetTypes: [TargetType]? {
      if case .dataset(_, let targetTypes) = self.value { return targetTypes }
      return nil
    }
  }

  /// Who or what is granted access.
  public var entity: Entity

  /// The granted role, or `nil` for authorized views, routines, and datasets.
  public var role: Role?

  /// The condition under which access is granted, or `nil` for unconditional access.
  ///
  /// Conditional entries are returned only when the request asks for access policy
  /// version 3.
  public var condition: Expr?

  /// Creates an access control entry.
  public init(_ entity: Entity, role: Role? = nil, condition: Expr? = nil) {
    self.entity = entity
    self.role = role
    self.condition = condition
  }
}
