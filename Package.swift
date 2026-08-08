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

import Foundation
import PackageDescription

// The package file for the `google-cloud-swift` monorepo.
//
// This file is only used for development, each package in the `generated/*` and `packages/*`
// subdirectories will have its own repository, this file will play no role in them.
//
// The file uses a helper function to create the full list of packages. The function returns a
// different value in CI builds, so we can compile all the packages using SPM. In the development
// environment this is too slow.

// A generated package description.
//
// This is just enough information to populate the `Package` data structure. It needs both the
// package path and its
struct Generated {
  public let name: String
  public let module: String
  public var traits: Set<Package.Dependency.Trait>

  init(name: String, module: String, traits: [String] = []) {
    self.name = name
    self.module = module
    self.traits = Set(traits.map { .init(name: $0) })
  }
}

let generated: [Generated] = generatedPackages()

let generatedDependencies: [Package.Dependency] = generated.map {
  let path = "./generated/\($0.name)"
  if $0.traits.isEmpty {
    return .package(path: path)
  }
  return .package(path: path, traits: $0.traits)
}

let generatedModules: [Target.Dependency] = generated.map {
  .product(name: $0.module, package: $0.name)
}

let package = Package(
  name: "GoogleCloudSwift",
  platforms: [
    .macOS(.v15)
  ],
  traits: [
    "IntegrationTests"
  ],
  dependencies: [
    // Only used for development.
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
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
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
  ] + generatedDependencies,
  targets: [
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        .product(name: "GoogleCloudAuth", package: "auth")
      ],
    ),
    .testTarget(
      name: "AllModules",
      dependencies: [.product(name: "UserGuide", package: "guide")] + generatedModules,
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

func generatedPackages() -> [Generated] {
  let fullBuild = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_FULL_BUILD"] == "true"
  if fullBuild {
    return generatedPackagesFull()
  }
  return generatedPackagesStatic()
}

func generatedPackagesStatic() -> [Generated] {
  return [
    .init(name: "google-cloud-location", module: "GoogleCloudLocation"),
    .init(name: "google-iam-v1", module: "GoogleIAMV1"),
    .init(name: "google-cloud-secretmanager-v1", module: "GoogleCloudSecretManagerV1"),
    .init(name: "google-cloud-security-publicca-v1", module: "GoogleCloudSecurityPublicCAV1"),
    .init(name: "google-cloud-workflows-v1", module: "GoogleCloudWorkflowsV1"),
    .init(
      name: "google-cloud-compute-v1", module: "GoogleCloudComputeV1",
      traits: ["Instances", "Images", "ZoneOperations"]),
  ]
}

func generatedPackagesFull() -> [Generated] {
  var generated: [Generated] = []
  let fileManager = FileManager.default
  let found = try? fileManager.contentsOfDirectory(atPath: "./generated")
  let prefix = "  name: \""
  let suffix = "\","
  for name in (found ?? []) {
    let package = URL(fileURLWithPath: "generated").appending(path: name).appending(
      path: "Package.swift")
    do {
      let contents = try String(contentsOf: package, encoding: .utf8)
      let matching = contents.split(separator: "\n").first(where: {
        $0.starts(with: prefix) && $0.hasSuffix(suffix)
      }).map({ r in
        var value = String(r)
        value.removeFirst(prefix.count)
        value.removeLast(suffix.count)
        return value
      })
      print("name=\(name) pkg=\(matching ?? "--- a ---")")
      if let pkg = matching {
        generated.append(.init(name: name, module: pkg))
      }
    } catch {
      // Ignore I/O errors, including missing files, in the development environment this is common,
      // as working in multiple branches may create empty directories.
      continue
    }
  }

  return generated  // generatedPackagesStatic()
}
