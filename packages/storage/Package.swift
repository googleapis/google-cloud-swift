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
  traits: [
    "IntegrationTests"
  ],
  dependencies: [
    .package(path: "../auth"),
    .package(path: "../gax"),
    .package(path: "../wkt"),
    .package(path: "../../generated/google-rpc"),
    .package(path: "../../generated/google-longrunning"),
    .package(path: "../../generated/google-type"),
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
    .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.23.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
  ],
  targets: [
    .target(
      name: "GoogleCloudStorage",
      dependencies: [
        .product(name: "GoogleCloudAuth", package: "auth"),
        .product(name: "GoogleCloudGax", package: "gax"),
        .product(name: "GoogleCloudWkt", package: "wkt"),
        .product(name: "GoogleCloudWktConvert", package: "wkt"),
        .product(name: "GoogleLongRunning", package: "google-longrunning"),
        .product(name: "GoogleType", package: "google-type"),
        .product(name: "Logging", package: "swift-log"),
        "StorageControlProtos",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "Crypto", package: "swift-crypto"),
      ],
      path: "Sources/GoogleCloudStorage"
    ),
    .testTarget(
      name: "GoogleCloudStorageTests",
      dependencies: [
        "GoogleCloudStorage",
        "StorageControlProtos",
      ],
      path: "Tests",
      exclude: ["IntegrationTests"]
    ),
    .testTarget(
      name: "GoogleCloudStorageIntegrationTests",
      dependencies: [
        "GoogleCloudStorage"
      ],
      path: "Tests/IntegrationTests"
    ),
    .target(
      name: "StorageControlProtos",
      dependencies: [
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "GRPC", package: "grpc-swift"),
      ],
      path: "Sources/generated/StorageControlProtos"
    ),
  ]
)
