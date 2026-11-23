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
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .strictMemorySafety(),
]

let package = Package(
  name: "PubSubConformanceProxy",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(path: "../../pkgs/swift-google-cloud-pubsub"),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-auth",
      path: "pkgs/swift-google-auth",
      from: "0.7.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-gax",
      path: "pkgs/swift-google-gax",
      from: "0.7.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-wkt",
      path: "pkgs/swift-google-wkt",
      from: "0.7.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-rpc",
      path: "generated/swift-google-rpc",
      from: "0.7.0"
    ),
    .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.3.0"),
    .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.3.0"),
    .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.3.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.1"),
  ],
  targets: [
    .target(
      name: "PubSubConformanceProtos",
      dependencies: [
        .product(name: "SwiftProtobuf", package: "swift-protobuf")
      ],
      path: "Generated/PubSubConformanceProtos"
    ),
    .target(
      name: "PubSubConformanceProxyCore",
      dependencies: [
        "PubSubConformanceProtos",
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleCloudPubSub", package: "swift-google-cloud-pubsub"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleRpc", package: "swift-google-rpc"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "Sources/PubSubConformanceProxyCore",
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "PubSubConformanceProxy",
      dependencies: [
        "PubSubConformanceProxyCore"
      ],
      path: "Sources/PubSubConformanceProxy",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "PubSubConformanceProxyTests",
      dependencies: [
        "PubSubConformanceProtos",
        "PubSubConformanceProxyCore",
        .product(name: "GoogleCloudPubSub", package: "swift-google-cloud-pubsub"),
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
      ],
      path: "Tests/PubSubConformanceProxyTests",
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
