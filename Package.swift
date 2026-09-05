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

let generated: [Generated] = selectGeneratedPackages()

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
  dependencies: [
    // Reference local packages via paths
    .package(url: "https://github.com/googleapis/swift-google-auth", from: "0.0.0-preview"),
    .package(path: "./packages/swift-google-gax"),
    .package(url: "https://github.com/googleapis/swift-google-wkt", from: "0.1.0-preview"),
    .package(path: "./packages/swift-google-cloud-storage"),
    .package(path: "./guide"),
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-nio", from: "2.101.0"),
    // Only used for development.
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
  ] + generatedDependencies,
  targets: [
    .testTarget(
      name: "AllModules",
      dependencies: [
        .product(name: "UserGuide", package: "guide"),
        .product(name: "GoogleCloudAuth", package: "swift-google-auth"),
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
      ] + generatedModules,
    ),
    .testTarget(
      name: "Discovery",
      dependencies: [
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt")
      ],
      exclude: ["disco/"],
    ),
    .testTarget(
      name: "ProtoJSON",
      dependencies: [
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
      ],
      exclude: ["protos/"],
    ),
    .testTarget(
      name: "DiscoveryBasedClient",
      dependencies: [
        .product(name: "GoogleCloudComputeV1", package: "swift-google-cloud-compute-v1"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        "GoogleCloudTestHelpers",
      ],
      exclude: ["README.md"],
    ),
    .testTarget(
      name: "ProtoBasedClient",
      dependencies: [
        .product(
          name: "GoogleCloudSecretManagerV1", package: "swift-google-cloud-secretmanager-v1"),
        .product(name: "GoogleCloudWorkflowsV1", package: "swift-google-cloud-workflows-v1"),
        .product(name: "GoogleCloudLocation", package: "swift-google-cloud-location"),
        .product(name: "GoogleIAMV1", package: "swift-google-iam-v1"),
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        .product(name: "GoogleCloudStorage", package: "swift-google-cloud-storage"),
        "GoogleCloudTestHelpers",
        .product(name: "InMemoryLogging", package: "swift-log"),
      ],
      exclude: ["README.md"],
    ),
    .testTarget(
      name: "Any",
      dependencies: [
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        .product(
          name: "GoogleCloudSecretManagerV1", package: "swift-google-cloud-secretmanager-v1"),
      ],
    ),
    .testTarget(
      name: "QueryParameter",
      dependencies: [
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        .product(
          name: "GoogleCloudSecurityPublicCAV1", package: "swift-google-cloud-security-publicca-v1"),
      ],
    ),
    .executableTarget(
      name: "Endurance",
      dependencies: [
        .product(
          name: "GoogleCloudSecretManagerV1", package: "swift-google-cloud-secretmanager-v1"),
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        "GoogleCloudTestHelpers",
      ],
      path: "Tests/Endurance",
      exclude: ["README.md", "endurance-test.service"]
    ),
    .executableTarget(
      name: "StorageW1R3",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "GoogleCloudStorage", package: "swift-google-cloud-storage"),
        .product(name: "GoogleCloudAuth", package: "swift-google-auth"),
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "NIOCore", package: "swift-nio"),
      ],
      path: "Tests/StorageW1R3",
      exclude: ["README.md"]
    ),
    .target(
      name: "GoogleCloudTestHelpers",
      dependencies: [
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(name: "InMemoryLogging", package: "swift-log"),
      ],
    ),
    .target(
      name: "StorageSamples",
      dependencies: [
        .product(name: "GoogleCloudStorage", package: "swift-google-cloud-storage"),
        .product(name: "GoogleCloudAuth", package: "swift-google-auth"),
        .product(name: "GoogleCloudGax", package: "swift-google-gax"),
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "GoogleIAMV1", package: "swift-google-iam-v1"),
        .product(name: "GoogleType", package: "swift-google-type"),
      ],
    ),
    .testTarget(
      name: "StorageSamplesDriver",
      dependencies: [
        "StorageSamples",
        .product(name: "GoogleCloudStorage", package: "swift-google-cloud-storage"),
        .product(name: "Logging", package: "swift-log"),
      ],
      path: "Tests/StorageSamplesDriver",
    ),
  ]
)

// A generated package description.
//
// This is just enough information to populate the `Package` data structure. It needs both the
// package path, its product [^1], and any (optional) traits that we enable for the tests in
// `Tests/`.
//
// [^1]: in general, packages have many products, but our packages in `generated/*` only have one.
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

/// Finds the generated packages used for the build.
func selectGeneratedPackages() -> [Generated] {
  let fullBuild = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_FULL_BUILD"] == "true"
  if fullBuild {
    return generatedPackagesFull()
  }
  return generatedPackagesStatic()
}

/// The packages required to build `Tests/`.
///
/// The tests, particularly the integration tests, use a relatively small set of packages. To find
/// out how we picked which APIs and packages to use in the integration tests, see the README files
/// for each test.
func generatedPackagesStatic() -> [Generated] {
  return [
    .init(name: "swift-google-cloud-location", module: "GoogleCloudLocation"),
    .init(name: "swift-google-iam-v1", module: "GoogleIAMV1"),
    .init(name: "swift-google-type", module: "GoogleType"),
    .init(name: "swift-google-cloud-secretmanager-v1", module: "GoogleCloudSecretManagerV1"),
    .init(name: "swift-google-cloud-security-publicca-v1", module: "GoogleCloudSecurityPublicCAV1"),
    .init(name: "swift-google-cloud-workflows-v1", module: "GoogleCloudWorkflowsV1"),
    .init(
      name: "swift-google-cloud-compute-v1", module: "GoogleCloudComputeV1",
      traits: ["Instances", "Images", "ZoneOperations"]),
  ]
}

/// Finds all the packages available in the generated/ subdirectory.
///
/// These roughly corresponds to GAPICs, but also include type-only packages.
func generatedPackagesFull() -> [Generated] {
  let prefix = "  name: \""
  let suffix = "\","

  var generated: [Generated] = generatedPackagesStatic()
  let skipped = Set(generated.map { $0.name })

  let generatedDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("generated")
  let found = try? FileManager.default.contentsOfDirectory(
    at: generatedDir, includingPropertiesForKeys: nil)
  for name in (found ?? []) {
    if skipped.contains(name.lastPathComponent) {
      // The package is statically known, skip opening the directory.
      continue
    }
    let packagePath = name.appendingPathComponent("Package.swift")
    do {
      let contents = try String(contentsOf: packagePath, encoding: .utf8)
      let matching = contents.split(separator: "\n").first(where: {
        $0.starts(with: prefix) && $0.hasSuffix(suffix)
      }).map({ r in
        var value = String(r)
        value.removeFirst(prefix.count)
        value.removeLast(suffix.count)
        return value
      })
      if let pkg = matching {
        generated.append(.init(name: name.lastPathComponent, module: pkg))
      }
    } catch {
      // Ignore I/O errors, including missing files, in the development environment this is common,
      // as working in multiple branches may create empty directories.
      continue
    }
  }

  return generated.sorted(by: { (a, b) in a.name < b.name })
}
