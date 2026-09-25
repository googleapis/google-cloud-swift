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
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .strictMemorySafety(),
]

let package = Package(
  name: "GoogleWKT",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GoogleWKT", targets: ["GoogleWKT"]),
    .library(name: "GoogleWKTConvert", targets: ["GoogleWKTConvert"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swift-extras/swift-extras-base64", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
  ],

  targets: [
    .target(
      name: "GoogleWKT",
      dependencies: [
        .product(name: "ExtrasBase64", package: "swift-extras-base64")
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "GoogleWKTConvert",
      dependencies: [
        "GoogleWKT",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      swiftSettings: swiftSettings
    ),

    .testTarget(
      name: "GoogleWKTTests",
      dependencies: [
        "GoogleWKT",
        "GoogleWKTConvert",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "Tests",
      swiftSettings: swiftSettings
    ),
  ]
)
