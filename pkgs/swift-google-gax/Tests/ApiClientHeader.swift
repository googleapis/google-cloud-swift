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
@_spi(GoogleCloudInternal) @testable import GoogleGax
import Testing

@Suite struct ApiClientHeader {
  @Test(arguments: ["1.2.3", "2.3.4", "0.0.0-preview"])
  func gapic(version: String) {
    let got = _gapicApiClientHeader(packageVersion: version)
    #expect(got.contains("gl-swift/"), "got=\(got)")
    #expect(got.contains("gapic/\(version)"), "got=\(got)")
    #expect(got.contains("gax/"), "got=\(got)")
  }

  @Test(arguments: ["1.2.3", "2.3.4", "0.0.0-preview"])
  func veneer(version: String) {
    let got = _veneerApiClientHeader(packageVersion: version)
    #expect(got.contains("gl-swift/"), "got=\(got)")
    #expect(got.contains("gccl/\(version)"), "got=\(got)")
    #expect(got.contains("gax/"), "got=\(got)")
  }

  @Test func apiClientHeaderHelper() {
    let got = _apiClientHeader(packageVersion: "1.0.0", libraryType: "custom-lib")
    #expect(got.contains("gl-swift/"))
    #expect(got.contains("gax/"))
    #expect(got.contains("custom-lib/1.0.0"))
  }

  @Test func defaultHeader() {
    let header = _ApiClientHeader()
    let built = header.build()
    #expect(built.contains("gl-swift/"))
    #expect(built.contains("gax/"))
    #expect(!built.contains("grpc/"))
    #expect(!built.contains("gapic/"))
    #expect(!built.contains("pb/"))
    #expect(header.description == built)
  }

  @Test func customTokens() {
    var header = _ApiClientHeader()
    header.setToken(.grpc, version: "1.2.3")
    header.setToken(.protobuf, version: "1.28.2")
    header.setToken(.custom("auth"), version: "0.5.0")
    header.setToken(.custom("cred-type"), version: "sa")
    header.setToken(.custom("custom-sdk"), version: "3.4.5")

    let str = header.build()
    #expect(str.contains("grpc/1.2.3"))
    #expect(str.contains("pb/1.28.2"))
    #expect(str.contains("auth/0.5.0"))
    #expect(str.contains("cred-type/sa"))
    #expect(str.contains("custom-sdk/3.4.5"))
    #expect(header.description == str)
  }

  @Test func updateExistingToken() {
    var header = _ApiClientHeader()
    header.setToken(.gax, version: "9.9.9")
    let built = header.build()
    #expect(built.contains("gax/9.9.9"))
  }

  @Test func customTokenNormalizesStandardToken() {
    var header = _ApiClientHeader()
    header.setToken(.custom("gl-swift"), version: "6.3.0")
    header.setToken(.custom("gax"), version: "9.9.9")
    header.setToken(.custom("pb"), version: "1.28.2")
    let built = header.build()
    #expect(built.contains("gl-swift/6.3.0"))
    #expect(built.contains("gax/9.9.9"))
    #expect(built.contains("pb/1.28.2"))
  }

  @Test func equality() {
    var header1 = _ApiClientHeader()
    header1.setToken(.gapic, version: "1.0.0")
    var header2 = _ApiClientHeader()
    header2.setToken(.gapic, version: "1.0.0")
    #expect(header1 == header2)

    var header3 = _ApiClientHeader()
    header3.setToken(.gapic, version: "2.0.0")
    #expect(header1 != header3)
  }

  @Test func tokenOrdering() {
    var header = _ApiClientHeader()
    header.setToken(.custom("custom"), version: "1.0.0")
    header.setToken(.custom("auth"), version: "0.5.0")
    header.setToken(.protobuf, version: "1.28.2")
    header.setToken(.grpc, version: "1.60.0")
    header.setToken(.gapic, version: "1.0.0")
    header.setToken(.gccl, version: "2.0.0")

    let built = header.build()
    let tokens = built.split(separator: " ").map { String($0.split(separator: "/")[0]) }
    #expect(
      tokens == [
        "gl-swift",
        "gccl",
        "gapic",
        "gax",
        "grpc",
        "pb",
        "auth",
        "custom",
      ])
  }

  @Test func swiftVersionTracking() {
    let runtime = swiftRuntimeVersion()
    let semver =
      #/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9a-zA-Z.-]+)?(?:\+[0-9a-zA-Z.-]+)?$/#
    #expect(runtime.wholeMatch(of: semver) != nil)
  }
}
