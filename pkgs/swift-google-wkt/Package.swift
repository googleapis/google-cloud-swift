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
  name: "GoogleCloudWKT",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GoogleCloudWKT", targets: ["GoogleCloudWKT"]),
    .library(name: "GoogleCloudWKTConvert", targets: ["GoogleCloudWKTConvert"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swift-extras/swift-extras-base64", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
  ],

  targets: [
    .target(
      name: "GoogleCloudWKT",
      dependencies: [
        .product(name: "ExtrasBase64", package: "swift-extras-base64")
      ]
    ),
    .target(
      name: "GoogleCloudWKTConvert",
      dependencies: [
        "GoogleCloudWKT",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ]
    ),

    .testTarget(
      name: "GoogleCloudWKTTests",
      dependencies: [
        "GoogleCloudWKT",
        "GoogleCloudWKTConvert",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "Tests"
    ),
  ]
)
