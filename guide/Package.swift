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
  name: "UserGuide",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "UserGuide", targets: ["UserGuide"])
  ],
  dependencies: [
    .package(url: "https://github.com/googleapis/swift-google-auth", from: "0.0.0-preview"),
    .package(path: "../packages/swift-google-gax"),
    .package(path: "../generated/swift-google-cloud-secretmanager-v1"),
    .package(path: "../generated/swift-google-cloud-language-v2"),
    .package(path: "../generated/swift-google-cloud-workflows-v1"),
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
  ],
  targets: [
    .target(
      name: "UserGuide",
      dependencies: [
        .product(name: "GoogleCloudAuth", package: "swift-google-auth"),
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(
          name: "GoogleCloudSecretManagerV1", package: "swift-google-cloud-secretmanager-v1"),
        .product(name: "GoogleCloudLanguageV2", package: "swift-google-cloud-language-v2"),
        .product(name: "GoogleCloudWorkflowsV1", package: "swift-google-cloud-workflows-v1"),
        .product(name: "Logging", package: "swift-log"),
      ]
    )
  ]
)
