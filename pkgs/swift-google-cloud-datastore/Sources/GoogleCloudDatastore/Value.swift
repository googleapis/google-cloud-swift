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
public import GoogleType
public import GoogleWKT

/// Represents one of the 11 supported Cloud Datastore property value types.
public enum Value: Sendable, Equatable {
  /// Explicit null value (`google.protobuf.NullValue`).
  case null
  /// Boolean value (`bool`).
  case bool(Bool)
  /// 64-bit signed integer (`int64`).
  case int64(Int64)
  /// 64-bit IEEE 754 floating-point number (`double`).
  case double(Double)
  /// UTC timestamp (`google.protobuf.Timestamp`), stored at microsecond precision.
  case timestamp(GoogleWKT.WKTTimestamp)
  /// UTF-8 string (`string`). Max 1,500 bytes if indexed; up to 1 MiB if unindexed.
  case string(String)
  /// Raw byte array (`bytes`). Max 1,500 bytes if indexed; up to 1 MiB if unindexed.
  case bytes(Data)
  /// Geographic coordinates (`google.type.LatLng`).
  case geoPoint(GoogleType.LatLng)
  /// Reference to a Datastore `Key` (`google.datastore.v1.Key`).
  case key(Key)
  /// Ordered list of property values (`google.datastore.v1.ArrayValue`).
  /// Note: Datastore prohibits directly nested arrays (`.array` cannot directly contain `.array`).
  case array([PropertyValue])
  /// Nested embedded entity (`google.datastore.v1.Entity`), with or without a `Key`.
  indirect case entity(EmbeddedEntity)
}

/// A Datastore property value together with its indexing and wire metadata.
public struct PropertyValue: Sendable, Equatable {
  /// The typed value of the property.
  public var value: GoogleCloudDatastore.Value

  /// If `true`, prevents Datastore from indexing this property value in built-in and composite indexes.
  public var excludeFromIndexes: Bool

  /// Internal wire `meaning` preserved across read-modify-write cycles.
  var meaning: Int32?

  /// Creates a `PropertyValue`.
  public init(_ value: GoogleCloudDatastore.Value, excludeFromIndexes: Bool = false) {
    self.value = value
    self.excludeFromIndexes = excludeFromIndexes
    self.meaning = nil
  }

  init(
    _ value: GoogleCloudDatastore.Value, excludeFromIndexes: Bool = false, meaning: Int32? = nil
  ) {
    self.value = value
    self.excludeFromIndexes = excludeFromIndexes
    self.meaning = meaning
  }

  /// Convenience factory for creating an unindexed property value (`excludeFromIndexes = true`).
  public static func unindexed(_ value: GoogleCloudDatastore.Value) -> Self {
    Self(value, excludeFromIndexes: true)
  }

  /// If this property value represents an index-projected timestamp (`meaning == 18` with an `int64`
  /// microsecond value) or a direct `.timestamp`, returns the corresponding `WKTTimestamp`.
  public var projectedTimestamp: GoogleWKT.WKTTimestamp? {
    switch value {
    case .timestamp(let ts):
      return ts
    case .int64(let micros) where meaning == 18:
      var seconds = micros / 1_000_000
      var remMicros = micros % 1_000_000
      if remMicros < 0 {
        seconds -= 1
        remMicros += 1_000_000
      }
      return try? GoogleWKT.WKTTimestamp(seconds: seconds, nanos: Int32(remMicros * 1_000))
    default:
      return nil
    }
  }
}

extension Value: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) {
    self = .null
  }
}

extension Value: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension Value: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) {
    self = .int64(value)
  }
}

extension Value: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .double(value)
  }
}

extension Value: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension Value: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: PropertyValue...) {
    self = .array(elements)
  }
}

extension Value: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, PropertyValue)...) {
    var props: [String: PropertyValue] = [:]
    for (k, v) in elements {
      props[k] = v
    }
    self = .entity(EmbeddedEntity(properties: props))
  }
}

extension PropertyValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) {
    self.init(.null)
  }
}

extension PropertyValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self.init(.bool(value))
  }
}

extension PropertyValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) {
    self.init(.int64(value))
  }
}

extension PropertyValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self.init(.double(value))
  }
}

extension PropertyValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(.string(value))
  }
}

extension PropertyValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: PropertyValue...) {
    self.init(.array(elements))
  }
}

extension PropertyValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, PropertyValue)...) {
    var props: [String: PropertyValue] = [:]
    for (k, v) in elements {
      props[k] = v
    }
    self.init(.entity(EmbeddedEntity(properties: props)))
  }
}
