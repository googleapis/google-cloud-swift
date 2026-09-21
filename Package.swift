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
// This file is only used for development, each package in the `generated/*` and `pkgs/*`
// subdirectories will have its own repository, this file will play no role in them.
//
// The file uses a helper function to create the full list of packages. The function returns a
// different value in CI builds, so we can compile all the packages using SPM. In the development
// environment this is too slow.

let selected: SelectedPackages = selectGeneratedPackages()

let generatedDependencies: [Package.Dependency] = selected.forDependencies.map {
  let path = "./generated/\($0.name)"
  if $0.traits.isEmpty {
    return .package(path: path)
  }
  return .package(path: path, traits: $0.traits)
}

let generatedModules: [Target.Dependency] = selected.forTarget.map {
  .product(name: $0.module, package: $0.name)
}

let baseModules: [Target.Dependency] =
  selected.includeBaseModules
  ? [
    .product(name: "GoogleAuth", package: "swift-google-auth"),
    .product(name: "GoogleGax", package: "swift-google-gax"),
    .product(name: "GoogleWKT", package: "swift-google-wkt"),
  ] : []

// The "mixin" packages, e.g. `swift-google-iam-v1`, are in `generated/`, and
// `generatedPackagesStatic()` always includes them as path dependencies.
// Declaring both a remote URL and a path dependency for the same package makes
// SwiftPM dependency resolution fail, so this list must not reference them.
let baseDependencies: [Package.Dependency] = [
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
  // Reference local packages via paths
  .package(path: "./pkgs/swift-google-cloud-storage"),
  .package(path: "./guide"),
  .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
  .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
  .package(url: "https://github.com/apple/swift-nio", from: "2.101.0"),
  // Only used for development.
  .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
]

let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("InternalImportsByDefault")
]

let package = Package(
  name: "GoogleCloudSwift",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: baseDependencies + generatedDependencies,
  targets: [
    .testTarget(
      name: "AllModules",
      dependencies: [
        .product(name: "UserGuide", package: "guide")
      ] + baseModules + generatedModules,
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "Discovery",
      dependencies: [
        .product(name: "GoogleWKT", package: "swift-google-wkt")
      ],
      exclude: ["disco/"],
    ),
    .testTarget(
      name: "ProtoJSON",
      dependencies: [
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
      ],
      exclude: ["protos/"],
    ),
    .testTarget(
      name: "DiscoveryBasedClient",
      dependencies: [
        .product(name: "GoogleCloudComputeV1", package: "swift-google-cloud-compute-v1"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
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
        .product(
          name: "GoogleCloudBuildV1", package: "swift-google-devtools-cloudbuild-v1"),
        .product(name: "GoogleCloudLocation", package: "swift-google-cloud-location"),
        .product(name: "GoogleIAMV1", package: "swift-google-iam-v1"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleCloudStorage", package: "swift-google-cloud-storage"),
        "GoogleCloudTestHelpers",
        .product(name: "InMemoryLogging", package: "swift-log"),
      ],
      exclude: ["README.md"],
    ),
    // The target name doubles as a module name, so it cannot be `Any`: the
    // per-target test runner generated by Swift Build fails to `import Any`.
    .testTarget(
      name: "AnyTests",
      dependencies: [
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(
          name: "GoogleCloudSecretManagerV1", package: "swift-google-cloud-secretmanager-v1"),
      ],
      path: "Tests/Any",
    ),
    .testTarget(
      name: "QueryParameter",
      dependencies: [
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(
          name: "GoogleCloudSecurityPublicCAV1", package: "swift-google-cloud-security-publicca-v1"),
      ],
    ),
    .testTarget(
      name: "Auth",
      dependencies: [
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleIAMCredentialsV1", package: "swift-google-iam-credentials-v1"),
        "GoogleCloudTestHelpers",
      ],
      path: "Tests/Auth",
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "Endurance",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(
          name: "GoogleCloudSecretManagerV1", package: "swift-google-cloud-secretmanager-v1"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
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
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "Logging", package: "swift-log"),
      ],
      path: "Tests/StorageW1R3",
      exclude: ["README.md"]
    ),
    .target(
      name: "GoogleCloudTestHelpers",
      dependencies: [
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "InMemoryLogging", package: "swift-log"),
        .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "StorageSamples",
      dependencies: [
        .product(name: "GoogleCloudStorage", package: "swift-google-cloud-storage"),
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
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
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "RequestBody",
      dependencies: [
        .product(name: "GoogleAuth", package: "swift-google-auth"),
        .product(name: "GoogleGax", package: "swift-google-gax"),
        .product(name: "GoogleWKT", package: "swift-google-wkt"),
        .product(name: "GoogleIAMV1", package: "swift-google-iam-v1"),
        .product(
          name: "GoogleCloudSecretManagerV1", package: "swift-google-cloud-secretmanager-v1"),
        .product(name: "GoogleCloudBuildV1", package: "swift-google-devtools-cloudbuild-v1"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        "GoogleCloudTestHelpers",
      ],
      exclude: ["README.md"],
      swiftSettings: swiftSettings
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

struct SelectedPackages {
  let forDependencies: [Generated]
  let forTarget: [Generated]
  let includeBaseModules: Bool
}

/// Finds the generated packages to use in this build.
///
/// In standard local development workflows, only a minimal set of packages
/// is built (see `generatedPackagesStatic()`). That keeps the dependency
/// resolution and build times short-ish.
///
/// To preview documentation for an extra package, set
/// `GOOGLE_CLOUD_SWIFT_EXTRA_PACKAGES="<package-name>"`, e.g.:
/// `GOOGLE_CLOUD_SWIFT_EXTRA_PACKAGES="swift-google-cloud-vision-v1"`
///
/// To build all packages, set `GOOGLE_CLOUD_SWIFT_FULL_BUILD=true`.
///
/// In post-merge CI docs builds, `GOOGLE_CLOUD_SWIFT_BUILD_SHARD_COUNT` and
/// `GOOGLE_CLOUD_SWIFT_BUILD_SHARD_INDEX` are set by `ci/gcb/scripts/docs.sh`
/// to shard documentation generation across multiple builders.
func selectGeneratedPackages() -> SelectedPackages {
  let env = ProcessInfo.processInfo.environment
  if let extra = env["GOOGLE_CLOUD_SWIFT_EXTRA_PACKAGES"] {
    let extraSet = Set(extra.split(separator: " ").map(String.init))
    let staticPkgs = generatedPackagesStatic()
    if extraSet.isEmpty {
      return SelectedPackages(
        forDependencies: staticPkgs,
        forTarget: staticPkgs,
        includeBaseModules: true
      )
    }
    let all = generatedPackagesFull()
    let staticSet = Set(staticPkgs.map { $0.name })
    let pkgs =
      staticPkgs + all.filter { extraSet.contains($0.name) && !staticSet.contains($0.name) }
    return SelectedPackages(
      forDependencies: pkgs,
      forTarget: pkgs,
      includeBaseModules: true
    )
  }
  if let countStr = env["GOOGLE_CLOUD_SWIFT_BUILD_SHARD_COUNT"], let count = Int(countStr),
    count >= 1
  {
    let index = Int(env["GOOGLE_CLOUD_SWIFT_BUILD_SHARD_INDEX"] ?? "0") ?? 0
    let all = generatedPackagesFull()
    if count == 1 && index == 0 {
      return SelectedPackages(
        forDependencies: all,
        forTarget: all,
        includeBaseModules: true
      )
    }
    let staticPkgs = generatedPackagesStatic()
    let staticSet = Set(staticPkgs.map { $0.name })
    let sharded = all.enumerated().compactMap { (i, pkg) -> Generated? in
      (i % count == index) ? pkg : nil
    }
    let shardedExtra = sharded.filter { !staticSet.contains($0.name) }
    return SelectedPackages(
      forDependencies: staticPkgs + shardedExtra,
      forTarget: sharded,
      includeBaseModules: false
    )
  }
  let fullBuild = env["GOOGLE_CLOUD_SWIFT_FULL_BUILD"] == "true"
  if fullBuild {
    let all = generatedPackagesFull()
    return SelectedPackages(
      forDependencies: all,
      forTarget: all,
      includeBaseModules: true
    )
  }
  let staticPkgs = generatedPackagesStatic()
  return SelectedPackages(
    forDependencies: staticPkgs,
    forTarget: staticPkgs,
    includeBaseModules: true
  )
}

/// The packages always included in the build.
///
/// The tests, particularly the integration tests, use a relatively small set of packages. To find
/// out how we picked which APIs and packages to use in the integration tests, see the README files
/// for each test.
///
/// The list also includes the "mixin" packages. Most generated packages depend on them, and
/// declaring both a remote URL and a path dependency for the same package makes SwiftPM dependency
/// resolution fail. Including them here guarantees they always appear as path dependencies.
func generatedPackagesStatic() -> [Generated] {
  return [
    .init(name: "swift-google-cloud-location", module: "GoogleCloudLocation"),
    .init(name: "swift-google-cloud-secretmanager-v1", module: "GoogleCloudSecretManagerV1"),
    .init(name: "swift-google-cloud-security-publicca-v1", module: "GoogleCloudSecurityPublicCAV1"),
    .init(name: "swift-google-cloud-workflows-v1", module: "GoogleCloudWorkflowsV1"),
    .init(name: "swift-google-devtools-cloudbuild-v1", module: "GoogleCloudBuildV1"),
    .init(name: "swift-google-iam-credentials-v1", module: "GoogleIAMCredentialsV1"),
    .init(name: "swift-google-iam-v1", module: "GoogleIAMV1"),
    .init(name: "swift-google-longrunning", module: "GoogleLongRunning"),
    .init(name: "swift-google-type", module: "GoogleType"),
    .init(
      name: "swift-google-cloud-compute-v1", module: "GoogleCloudComputeV1",
      traits: ["Instances", "Images", "ZoneOperations"]),
  ]
}

/// Finds all the packages available in the generated/ subdirectory.
///
/// These roughly correspond to GAPICs, but also include type-only packages.
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

func localOrRemotePackage(url: String, path: String, from version: Version) -> Package.Dependency {
  if let env = Context.environment["GOOGLE_CLOUD_SWIFT_LOCAL_DEPS"], !env.isEmpty {
    let root = (env == "1" || env == "true") ? Context.packageDirectory : env
    return .package(path: "\(root)/\(path)")
  }
  return .package(url: url, from: version)
}
