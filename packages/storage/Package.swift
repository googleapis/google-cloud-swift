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
  name: "GoogleCloudStorage",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GoogleCloudStorage", targets: ["GoogleCloudStorage"])
  ],
  dependencies: [
    .package(path: "../auth"),
    .package(path: "../gax"),
    .package(path: "../wkt"),
    .package(path: "../../generated/google-iam-v1"),
    .package(path: "../../generated/google-rpc"),
    .package(path: "../../generated/google-longrunning"),
    .package(path: "../../generated/google-type"),
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.1"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
    .package(url: "https://github.com/apple/swift-nio", from: "2.101.0"),
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.36.0"),
  ],
  targets: [
    .target(
      name: "GoogleCloudStorage",
      dependencies: [
        .product(name: "GoogleCloudAuth", package: "auth"),
        .product(name: "GoogleCloudGax", package: "gax"),
        .product(name: "GoogleCloudGaxGRPC", package: "gax"),
        .product(name: "GoogleCloudWKT", package: "wkt"),
        .product(name: "GoogleCloudWKTConvert", package: "wkt"),
        .product(name: "GoogleIAMV1", package: "google-iam-v1"),
        .product(name: "GoogleLongRunning", package: "google-longrunning"),
        .product(name: "GoogleRpc", package: "google-rpc"),
        .product(name: "GoogleType", package: "google-type"),
        .product(name: "Logging", package: "swift-log"),
        "StorageControlProtos",
        "StorageProtos",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      path: "Sources/GoogleCloudStorage"
    ),
    .testTarget(
      name: "GoogleCloudStorageTests",
      dependencies: [
        "GoogleCloudStorage",
        "StorageControlProtos",
        "StorageProtos",
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      path: "Tests",
      exclude: ["IntegrationTests"]
    ),
    .testTarget(
      name: "GoogleCloudStorageIntegrationTests",
      dependencies: [
        "GoogleCloudStorage",
        .product(name: "GoogleCloudAuth", package: "auth"),
        .product(name: "GoogleCloudGax", package: "gax"),
        .product(name: "NIOCore", package: "swift-nio"),
      ],
      path: "Tests/IntegrationTests"
    ),
    .target(
      name: "StorageControlProtos",
      dependencies: [
        .product(name: "SwiftProtobuf", package: "swift-protobuf")
      ],
      path: "Sources/generated/StorageControlProtos"
    ),
    .target(
      name: "StorageProtos",
      dependencies: [
        .product(name: "SwiftProtobuf", package: "swift-protobuf")
      ],
      path: "Sources/generated/StorageProtos"
    ),
  ]
)
