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
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-auth",
      path: "pkgs/swift-google-auth",
      from: "0.3.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-gax",
      path: "pkgs/swift-google-gax",
      from: "0.3.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-cloud-secretmanager-v1",
      path: "generated/swift-google-cloud-secretmanager-v1",
      from: "0.3.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-cloud-language-v2",
      path: "generated/swift-google-cloud-language-v2",
      from: "0.3.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-cloud-workflows-v1",
      path: "generated/swift-google-cloud-workflows-v1",
      from: "0.3.0"
    ),
    localOrRemotePackage(
      url: "https://github.com/googleapis/swift-google-cloud-aiplatform-v1",
      path: "generated/swift-google-cloud-aiplatform-v1",
      from: "0.3.0"
    ),
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
  ],
  targets: [
    .target(
      name: "UserGuide",
      dependencies: [
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(
          name: "GoogleCloudSecretManagerV1", package: "swift-google-cloud-secretmanager-v1"),
        .product(name: "GoogleCloudLanguageV2", package: "swift-google-cloud-language-v2"),
        .product(name: "GoogleCloudWorkflowsV1", package: "swift-google-cloud-workflows-v1"),
        .product(name: "GoogleCloudAIPlatformV1", package: "swift-google-cloud-aiplatform-v1"),
        .product(name: "Logging", package: "swift-log"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("InternalImportsByDefault")
      ]
    )
  ]
)

func localOrRemotePackage(url: String, path: String, from version: Version) -> Package.Dependency {
  if let env = Context.environment["GOOGLE_CLOUD_SWIFT_LOCAL_DEPS"], !env.isEmpty {
    let root = (env == "1" || env == "true") ? "\(Context.packageDirectory)/.." : env
    return .package(path: "\(root)/\(path)")
  }
  return .package(url: url, from: version)
}
