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
  name: "GoogleCloudBigQuery",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GoogleCloudBigQuery", targets: ["GoogleCloudBigQuery"])
  ],
  dependencies: [
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-auth",
      path: "pkgs/swift-google-auth",
      from: "0.4.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-gax",
      path: "pkgs/swift-google-gax",
      from: "0.4.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-wkt",
      path: "pkgs/swift-google-wkt",
      from: "0.4.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-cloud-bigquery-v2",
      path: "generated/swift-google-cloud-bigquery-v2",
      from: "0.3.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-iam-v1",
      path: "generated/swift-google-iam-v1",
      from: "0.4.0"
    ),
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
    .package(url: "https://github.com/apple/swift-nio", from: "2.101.0"),
  ],
  targets: [
    .target(
      name: "GoogleCloudBigQuery",
      dependencies: [
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleCloudBigQueryV2", package: "swift-google-cloud-bigquery-v2"),
        .product(name: "GoogleIAMV1", package: "swift-google-iam-v1"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      path: "Sources/GoogleCloudBigQuery",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GoogleCloudBigQueryTests",
      dependencies: [
        "GoogleCloudBigQuery",
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleCloudBigQueryV2", package: "swift-google-cloud-bigquery-v2"),
        .product(name: "NIOCore", package: "swift-nio"),
      ],
      path: "Tests",
      exclude: ["IntegrationTests"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GoogleCloudBigQueryIntegrationTests",
      dependencies: [
        "GoogleCloudBigQuery",
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleCloudBigQueryV2", package: "swift-google-cloud-bigquery-v2"),
      ],
      path: "Tests/IntegrationTests",
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
