// swift-tools-version: 6.2
//
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

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("InternalImportsByDefault")
]

let package = Package(
  name: "GoogleGax",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GoogleGax", targets: ["GoogleGax"]),
    .library(name: "GoogleGaxGRPC", targets: ["GoogleGaxGRPC"]),
  ],
  dependencies: [
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-auth",
      path: "pkgs/swift-google-auth",
      from: "0.2.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-wkt",
      path: "pkgs/swift-google-wkt",
      from: "0.2.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-rpc",
      path: "generated/swift-google-rpc",
      from: "0.2.0"
    ),
    .package(url: "https://github.com/apple/swift-log", from: "1.14.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.6.0"),
    .package(url: "https://github.com/apple/swift-nio", from: "2.101.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
    .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.3.0"),
    .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.3.0"),
    .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.3.0"),
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.36.0"),
  ],
  targets: [
    .target(
      name: "CGoogleGaxCRC32C"
    ),
    .target(
      name: "GoogleGax",
      dependencies: [
        "CGoogleGaxCRC32C",
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleRpc", package: "swift-google-rpc"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOFoundationCompat", package: "swift-nio"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "GoogleGaxGRPC",
      dependencies: [
        "GoogleGax",
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleWKTConvert", package: "swift-google-wkt"),
        .product(name: "GoogleRpc", package: "swift-google-rpc"),
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GoogleGaxTests",
      dependencies: [
        "GoogleGax",
        "GoogleGaxGRPC",
        .product(name: "DequeModule", package: "swift-collections"),
        .product(name: "GoogleRpc", package: "swift-google-rpc"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleWKTConvert", package: "swift-google-wkt"),
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "Tests",
      swiftSettings: swiftSettings
    ),
  ]
)

func localOrRemotePackage(url: String, path: String, from version: Version) -> Package.Dependency {
  if let env = Context.environment["GOOGLE_CLOUD_SWIFT_LOCAL_DEPS"], !env.isEmpty {
    let root = (env == "1" || env == "true") ? "\(Context.packageDirectory)/../.." : env
    return .package(path: "\(root)/\(path)")
  }
  return .package(url: url, from: version)
}
