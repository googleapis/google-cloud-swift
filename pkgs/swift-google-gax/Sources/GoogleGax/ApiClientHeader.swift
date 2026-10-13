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

/// A builder and container for Google Cloud `x-goog-api-client` telemetry headers.
///
/// Google Cloud APIs use the `x-goog-api-client` header to collect client library
/// usage and adoption metrics. The header consists of a space-separated list of
/// `NAME "/" VERSION` tokens (e.g., `gl-swift/6.3.0 gapic/0.5.0 gax/0.5.0`).
///
/// Standard token names include:
/// - `gl-swift`: Swift standard library runtime version.
/// - `gccl`: Google Cloud Client Library (veneer) version.
/// - `gapic`: Generated GAPIC client library version.
/// - `gax`: Google API Extensions (GAX) version.
/// - `grpc`: gRPC transport version.
/// - `rest`: REST/HTTP transport version.
/// - `pb`: Swift Protobuf runtime version.
///
/// See [System Parameters](https://docs.cloud.google.com/apis/docs/system-parameters).
struct _ApiClientHeader: Sendable, Equatable, CustomStringConvertible {
  enum Token: Hashable, Sendable {
    case swiftLanguage
    case gccl
    case gapic
    case gax
    case grpc
    case rest
    case protobuf
    case custom(String)

    var name: String {
      switch self {
      case .swiftLanguage: return "gl-swift"
      case .gccl: return "gccl"
      case .gapic: return "gapic"
      case .gax: return "gax"
      case .grpc: return "grpc"
      case .rest: return "rest"
      case .protobuf: return "pb"
      case .custom(let name): return name
      }
    }

    var normalized: Token {
      guard case .custom(let name) = self else { return self }
      switch name {
      case "gl-swift": return .swiftLanguage
      case "gccl": return .gccl
      case "gapic": return .gapic
      case "gax": return .gax
      case "grpc": return .grpc
      case "rest": return .rest
      case "pb": return .protobuf
      default: return self
      }
    }

    fileprivate var sortRank: Int {
      switch self {
      case .swiftLanguage: return 0
      case .gccl: return 1
      case .gapic: return 2
      case .gax: return 3
      case .grpc, .rest: return 4
      case .protobuf: return 5
      case .custom: return 10
      }
    }
  }

  private var tokens: [Token: String]

  /// The standard HTTP header name (`x-goog-api-client`).
  static let headerName = _HeaderNames.apiClient

  /// Creates a header populated with default environment tokens (`gl-swift`, `gax`, and `rest`).
  init() {
    self.tokens = [
      .swiftLanguage: swiftRuntimeVersion(),
      .gax: gaxVersion(),
      .rest: gaxVersion(),
    ]
  }

  /// Sets or updates a token.
  mutating func setToken(_ token: Token, version: String) {
    self.tokens[token.normalized] = version
  }

  /// Formats the header into its canonical space-separated string representation.
  func build() -> String {
    self.tokens
      .sorted { $0.key < $1.key }
      .map { "\($0.key.name)/\($0.value)" }
      .joined(separator: " ")
  }

  var description: String { self.build() }
}

extension _ApiClientHeader.Token: Comparable {
  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.sortRank != rhs.sortRank {
      return lhs.sortRank < rhs.sortRank
    }
    return lhs.name < rhs.name
  }
}

@_spi(GoogleCloudInternal)
public func _gapicApiClientHeader(packageVersion: String) -> String {
  var header = _ApiClientHeader()
  header.setToken(.gapic, version: packageVersion)
  return header.build()
}

@_spi(GoogleCloudInternal)
public func _veneerApiClientHeader(packageVersion: String) -> String {
  var header = _ApiClientHeader()
  header.setToken(.gccl, version: packageVersion)
  return header.build()
}

// `_SwiftStdlibVersion` was introduced in Swift 5.6. Because this project only
// supports Swift 6.2+, we don't need to protect this call with availability guards.
func swiftRuntimeVersion() -> String {
  _SwiftStdlibVersion.current.description
}

func gaxVersion() -> String {
  return PackageVersion.version
}
