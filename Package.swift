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
  name: "GoogleCloudSwift",
  platforms: [
    .macOS(.v15)
  ],
  traits: [
    "IntegrationTests"
  ],
  dependencies: [
    // Reference local packages via paths
    .package(path: "./packages/auth"),
    .package(
      path: "./packages/gax",
      traits: [
        .trait(name: "IntegrationTests", condition: .when(traits: ["IntegrationTests"]))
      ],
    ),
    .package(path: "./packages/test-helpers"),
    .package(path: "./packages/wkt"),
    .package(path: "./packages/storage"),
    .package(path: "./guide"),
    .package(
      path: "./generated/google-cloud-compute-v1",
      traits: ["Instances", "Images", "ZoneOperations"],
    ),
    .package(path: "./generated/google-cloud-location"),
    .package(path: "./generated/google-iam-v1"),
    .package(path: "./generated/google-cloud-secretmanager-v1"),
    .package(path: "./generated/google-cloud-security-publicca-v1"),
    .package(path: "./generated/google-cloud-workflows-v1"),
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
    // Only used for development.
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
  ],
  targets: [
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        .product(name: "GoogleCloudAuth", package: "auth")
      ],
    ),
    .testTarget(
      name: "AllModules",
      dependencies: [.product(name: "UserGuide", package: "guide")],
    ),
    .testTarget(
      name: "Discovery",
      dependencies: [
        .product(name: "GoogleCloudWkt", package: "wkt")
      ],
      exclude: ["disco/"],
    ),
    .testTarget(
      name: "ProtoJSON",
      dependencies: [
        .product(name: "GoogleCloudGax", package: "gax"),
        .product(name: "GoogleCloudWkt", package: "wkt"),
      ],
      exclude: ["protos/"],
    ),
    .testTarget(
      name: "DiscoveryBasedClient",
      dependencies: [
        .product(name: "GoogleCloudComputeV1", package: "google-cloud-compute-v1"),
        .product(name: "GoogleCloudWkt", package: "wkt"),
        .product(name: "GoogleCloudTestHelpers", package: "test-helpers"),
      ],
      exclude: ["README.md"],
    ),
    .testTarget(
      name: "ProtoBasedClient",
      dependencies: [
        .product(name: "GoogleCloudSecretManagerV1", package: "google-cloud-secretmanager-v1"),
        .product(name: "GoogleCloudWorkflowsV1", package: "google-cloud-workflows-v1"),
        .product(name: "GoogleCloudLocation", package: "google-cloud-location"),
        .product(name: "GoogleIAMV1", package: "google-iam-v1"),
        .product(name: "GoogleCloudGax", package: "gax"),
        .product(name: "GoogleCloudWkt", package: "wkt"),
        .product(name: "GoogleCloudStorage", package: "storage"),
        .product(name: "GoogleCloudTestHelpers", package: "test-helpers"),
        .product(name: "InMemoryLogging", package: "swift-log"),
      ],
      exclude: ["README.md"],
    ),
    .testTarget(
      name: "Any",
      dependencies: [
        .product(name: "GoogleCloudWkt", package: "wkt"),
        .product(name: "GoogleCloudSecretManagerV1", package: "google-cloud-secretmanager-v1"),
      ],
    ),
    .testTarget(
      name: "QueryParameter",
      dependencies: [
        .product(name: "GoogleCloudGax", package: "gax"),
        .product(name: "GoogleCloudWkt", package: "wkt"),
        .product(
          name: "GoogleCloudSecurityPublicCAV1", package: "google-cloud-security-publicca-v1"),
      ],
    ),
  ]
)
