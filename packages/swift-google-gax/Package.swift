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

let package = Package(
  name: "GoogleCloudGax",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GoogleCloudGax", targets: ["GoogleCloudGax"]),
    .library(name: "GoogleCloudGaxGRPC", targets: ["GoogleCloudGaxGRPC"]),
  ],
  dependencies: [
    .package(url: "https://github.com/googleapis/swift-google-auth", from: "0.0.0-preview"),
    .package(url: "https://github.com/googleapis/swift-google-wkt", from: "0.1.0-preview"),
    .package(path: "../../generated/swift-google-rpc"),
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
      name: "GoogleCloudGax",
      dependencies: [
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "GoogleCloudAuth", package: "swift-google-auth"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        .product(name: "GoogleRpc", package: "swift-google-rpc"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOFoundationCompat", package: "swift-nio"),
      ]
    ),
    .target(
      name: "GoogleCloudGaxGRPC",
      dependencies: [
        "GoogleCloudGax",
        .product(name: "GoogleCloudAuth", package: "swift-google-auth"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        .product(name: "GoogleRpc", package: "swift-google-rpc"),
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ]
    ),
    .testTarget(
      name: "GoogleCloudGaxTests",
      dependencies: [
        "GoogleCloudGax",
        "GoogleCloudGaxGRPC",
        .product(name: "DequeModule", package: "swift-collections"),
        .product(name: "GoogleRpc", package: "swift-google-rpc"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        .product(name: "GoogleCloudWKTConvert", package: "swift-google-wkt"),
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "Tests",
    ),
  ]
)
