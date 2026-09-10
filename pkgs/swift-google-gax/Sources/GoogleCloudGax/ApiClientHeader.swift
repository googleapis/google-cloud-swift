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

func _apiClientHeader(packageVersion: String, libraryType: String) -> String {
  "gl-swift/apple-\(compilerVersion())-lang-\(swiftCompatVersion()) gax/\(gaxVersion()) rest/\(gaxVersion()) \(libraryType)/\(packageVersion)"
}

public func _gapicApiClientHeader(packageVersion: String) -> String {
  _apiClientHeader(packageVersion: packageVersion, libraryType: "gapic")
}

public func _veneerApiClientHeader(packageVersion: String) -> String {
  // gccl == Google Cloud Client Library
  _apiClientHeader(packageVersion: packageVersion, libraryType: "gccl")
}

func compilerVersion() -> String {
  // Apparently Swift does not have a macro or function to detect the compiler version.
  // This code is mildly annoying, but only requires updates every 5 years or so.
  #if compiler(>=11.0)
    return "11.x"
  #elseif compiler(>=10.0)
    return "10.x"
  #elseif compiler(>=9.0)
    return "9.x"
  #elseif compiler(>=8.0)
    return "8.x"
  #elseif compiler(>=7.0)
    return "7.x"
  #elseif compiler(>=6.0)
    return "6.x"
  #else
    // Stop compilation. Should not be that hard to keep this function up to date, we will need to
    // update our code to compile with each major release anyway.
    #error("This version of the Swift compiler is unknown or unsupported")
  #endif
}

func swiftCompatVersion() -> String {
  // Apparently Swift does not have a macro or function to detect the compiler version.
  // This code is mildly annoying, but only requires updates every 5 years or so.
  #if swift(>=11.0)
    return "11.x"
  #elseif swift(>=10.0)
    return "10.x"
  #elseif swift(>=9.0)
    return "9.x"
  #elseif swift(>=8.0)
    return "8.x"
  #elseif swift(>=7.0)
    return "7.x"
  #elseif swift(>=6.0)
    return "6.x"
  #else
    // Stop compilation. Should not be that hard to keep this function up to date, we will need to
    // update our code to compile with each major release anyway.
    #error("This version of Swift is unknown or unsupported")
  #endif
}

func gaxVersion() -> String {
  return PackageVersion.version
}
