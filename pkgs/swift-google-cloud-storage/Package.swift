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
  name: "GoogleCloudStorage",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GoogleCloudStorage", targets: ["GoogleCloudStorage"])
  ],
  dependencies: [
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-auth",
      path: "pkgs/swift-google-auth",
      from: "0.2.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-gax",
      path: "pkgs/swift-google-gax",
      from: "0.2.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-wkt",
      path: "pkgs/swift-google-wkt",
      from: "0.2.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-iam-v1",
      path: "generated/swift-google-iam-v1",
      from: "0.2.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-rpc",
      path: "generated/swift-google-rpc",
      from: "0.2.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-longrunning",
      path: "generated/swift-google-longrunning",
      from: "0.2.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-type",
      path: "generated/swift-google-type",
      from: "0.2.0"
    ),
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
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleGaxGRPC", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleWKTConvert", package: "swift-google-wkt"),
        .product(name: "GoogleIAMV1", package: "swift-google-iam-v1"),
        .product(name: "GoogleLongRunning", package: "swift-google-longrunning"),
        .product(name: "GoogleRpc", package: "swift-google-rpc"),
        .product(name: "GoogleType", package: "swift-google-type"),
        .product(name: "Logging", package: "swift-log"),
        "StorageControlProtos",
        "StorageProtos",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "_NIOFileSystem", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      path: "Sources/GoogleCloudStorage",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GoogleCloudStorageTests",
      dependencies: [
        "GoogleCloudStorage",
        "StorageControlProtos",
        "StorageProtos",
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleLongRunning", package: "swift-google-longrunning"),
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      path: "Tests",
      exclude: ["IntegrationTests"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GoogleCloudStorageIntegrationTests",
      dependencies: [
        "GoogleCloudStorage",
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "NIOCore", package: "swift-nio"),
      ],
      path: "Tests/IntegrationTests",
      swiftSettings: swiftSettings
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

func localOrRemotePackage(url: String, path: String, from version: Version) -> Package.Dependency {
  if let env = Context.environment["GOOGLE_CLOUD_SWIFT_LOCAL_DEPS"], !env.isEmpty {
    let root = (env == "1" || env == "true") ? "\(Context.packageDirectory)/../.." : env
    return .package(path: "\(root)/\(path)")
  }
  return .package(url: url, from: version)
}
