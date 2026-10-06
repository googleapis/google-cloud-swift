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
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .strictMemorySafety(),
]

let package = Package(
  name: "GoogleWKTConvert",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GoogleWKTConvert", targets: ["GoogleWKTConvert"])
  ],
  dependencies: [
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-wkt",
      path: "pkgs/swift-google-wkt",
      from: "0.4.0"
    ),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
  ],
  targets: [
    .target(
      name: "GoogleWKTConvert",
      dependencies: [
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GoogleWKTConvertTests",
      dependencies: [
        "GoogleWKTConvert",
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
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
