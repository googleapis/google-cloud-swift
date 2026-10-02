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
@_spi(GoogleCloudInternal) import GoogleGax
import Testing

@Suite struct BindingErrorTests {
  @Test func emptyBindingError() {
    let err = BindingError()
    #expect(err.description == "no matching URL path")
    #expect(err.paths.isEmpty)

    let reqErr: RequestError = .binding(BindingError())
    #expect(reqErr == .binding(BindingError()))
  }

  @Test func substitutionMismatchDescription() {
    let unset = SubstitutionMismatch(fieldName: "parent", problem: .unset)
    #expect(unset.description == "field 'parent' needs to be set")

    let unsetExpecting = SubstitutionMismatch(
      fieldName: "name",
      problem: .unsetExpecting("projects/*/secrets/*")
    )
    #expect(
      unsetExpecting.description
        == "field 'name' needs to be set and match the template: 'projects/*/secrets/*'"
    )

    let mismatch = SubstitutionMismatch(
      fieldName: "name",
      problem: .mismatchExpecting(actual: "bad-name", expected: "projects/*/secrets/*")
    )
    #expect(
      mismatch.description
        == "field 'name' should match the template: 'projects/*/secrets/*'; found: 'bad-name'"
    )

    let invalidVal = SubstitutionMismatch(fieldName: "region", problem: .invalidValue(actual: ".."))
    #expect(invalidVal.description == "Invalid value .. for region")

    let invalidSeg = SubstitutionMismatch(
      fieldName: "name", problem: .invalidSegments(actual: "projects/p/topics/a/../b")
    )
    #expect(
      invalidSeg.description
        == "Value for name must not contain segments that are exactly . or .."
    )
  }

  @Test func convenienceInitializersForInvalidPathValues() {
    let errVal = BindingError(fieldName: "region", invalidValue: "..")
    #expect(errVal.description == "Invalid value .. for region")

    let errSeg = BindingError(fieldName: "name", invalidSegments: "projects/p/topics/a/../b")
    #expect(
      errSeg.description == "Value for name must not contain segments that are exactly . or ..")
  }

  @Test func singlePathMismatchDescription() {
    let sub1 = SubstitutionMismatch(fieldName: "parent", problem: .unset)
    let sub2 = SubstitutionMismatch(
      fieldName: "name",
      problem: .mismatchExpecting(actual: "bad", expected: "projects/*")
    )
    let path = PathMismatch(substitutions: [sub1, sub2])
    #expect(
      path.description
        == "field 'parent' needs to be set AND field 'name' should match the template: 'projects/*'; found: 'bad'"
    )

    let bindingErr = BindingError(paths: [path])
    #expect(bindingErr.description == path.description)
  }

  @Test func multiplePathMismatchDescription() {
    let path1 = PathMismatch(substitutions: [
      SubstitutionMismatch(
        fieldName: "name",
        problem: .mismatchExpecting(actual: "proj/123", expected: "projects/*/secrets/*")
      )
    ])
    let path2 = PathMismatch(substitutions: [
      SubstitutionMismatch(
        fieldName: "name",
        problem: .mismatchExpecting(
          actual: "proj/123", expected: "projects/*/locations/*/secrets/*")
      )
    ])

    let bindingErr = BindingError(paths: [path1, path2])
    let expected =
      "at least one of the conditions must be met: (1) field 'name' should match the template: 'projects/*/secrets/*'; found: 'proj/123' OR (2) field 'name' should match the template: 'projects/*/locations/*/secrets/*'; found: 'proj/123'"
    #expect(bindingErr.description == expected)
  }

  @Test func pathMismatchBuilder() {
    var builder = _PathMismatchBuilder()

    // Matching value should not be recorded as a problem
    builder.maybeAdd(
      "projects/my-project/secrets/my-secret",
      matching: [.literal("projects/"), .singleWildcard, .literal("/secrets/"), .singleWildcard],
      fieldName: "name",
      expecting: "projects/*/secrets/*"
    )
    #expect(builder.build().substitutions.isEmpty)

    // Mismatched value should be recorded
    builder.maybeAdd(
      "invalid-resource-name",
      matching: [.literal("projects/"), .singleWildcard, .literal("/secrets/"), .singleWildcard],
      fieldName: "name",
      expecting: "projects/*/secrets/*"
    )
    let mismatch = builder.build()
    #expect(mismatch.substitutions.count == 1)
    #expect(
      mismatch.substitutions[0]
        == SubstitutionMismatch(
          fieldName: "name",
          problem: .mismatchExpecting(
            actual: "invalid-resource-name",
            expected: "projects/*/secrets/*"
          )
        )
    )

    // Unset or empty value should record unsetExpecting
    var builder2 = _PathMismatchBuilder()
    builder2.maybeAdd(
      "",
      matching: [.literal("projects/"), .singleWildcard],
      fieldName: "name",
      expecting: "projects/*"
    )
    builder2.maybeAdd(
      nil as String?,
      matching: [.literal("projects/"), .singleWildcard],
      fieldName: "parent",
      expecting: "projects/*"
    )
    let mismatch2 = builder2.build()
    #expect(mismatch2.substitutions.count == 2)
    #expect(
      mismatch2.substitutions[0]
        == SubstitutionMismatch(fieldName: "name", problem: .unsetExpecting("projects/*"))
    )
    #expect(
      mismatch2.substitutions[1]
        == SubstitutionMismatch(fieldName: "parent", problem: .unsetExpecting("projects/*"))
    )

    // Non-string fields
    var builder3 = _PathMismatchBuilder()
    builder3.maybeAdd(nil as Int?, fieldName: "page_size")
    builder3.maybeAdd(10 as Int?, fieldName: "max_results")
    let mismatch3 = builder3.build()
    #expect(mismatch3.substitutions.count == 1)
    #expect(
      mismatch3.substitutions[0] == SubstitutionMismatch(fieldName: "page_size", problem: .unset))
  }

  @Test func properties() {
    let sub = SubstitutionMismatch(fieldName: "field", problem: .unset)
    #expect(sub.fieldName == "field")
    #expect(sub.problem == .unset)

    let path = PathMismatch(substitutions: [sub])
    #expect(path.substitutions == [sub])

    let err = BindingError(paths: [path])
    #expect(err.paths == [path])
  }

  @Test func mockUsagePatterns() {
    // 1. Generic synthetic error in mock client
    let genericError: RequestError = .binding(BindingError())
    #expect(genericError == .binding(BindingError()))

    // 2. Specific single-field failure
    let singleFieldError = BindingError(fieldName: "parent", invalidValue: "")
    #expect(singleFieldError.description == "Invalid value  for parent")

    // 3. Multi-segment invalid relative path
    let multiSegmentError = BindingError(fieldName: "name", invalidSegments: "a/../b")
    #expect(
      multiSegmentError.description
        == "Value for name must not contain segments that are exactly . or ..")

    // 4. Multi-path detailed error
    let detailedError = BindingError(paths: [
      PathMismatch(substitutions: [
        SubstitutionMismatch(fieldName: "name", problem: .unset)
      ])
    ])
    #expect(detailedError.paths.count == 1)
    #expect(detailedError.paths[0].substitutions.count == 1)
  }

  @Test func debugDescriptionAndLocalizedError() {
    let sub = SubstitutionMismatch(fieldName: "name", problem: .unset)
    #expect(
      sub.debugDescription
        == "SubstitutionMismatch(fieldName: \"name\", problem: SubstitutionFail.unset)"
    )
    #expect(SubstitutionFail.unset.description == "unset")
    #expect(
      SubstitutionFail.unsetExpecting("pattern").description == "unset (expecting pattern)"
    )
    #expect(
      SubstitutionFail.mismatchExpecting(actual: "a", expected: "b").description
        == "mismatch (actual: a, expecting: b)"
    )
    #expect(SubstitutionFail.invalidValue(actual: "bad").description == "invalidValue (bad)")
    #expect(
      SubstitutionFail.invalidSegments(actual: "../").description == "invalidSegments (../)"
    )

    let path = PathMismatch(substitutions: [sub])
    #expect(path.debugDescription.contains("PathMismatch(substitutions:"))

    let err = BindingError(paths: [path])
    #expect(err.debugDescription.contains("BindingError(paths:"))

    let localized = err as LocalizedError
    #expect(localized.errorDescription == err.description)
    #expect(localized.failureReason == "The request failed to match any valid URL path template.")
    #expect(
      localized.recoverySuggestion
        == "Verify that all required fields in the request (such as 'name' or 'parent') are set and correctly formatted."
    )
    #expect(err.localizedDescription == err.description)
  }
}
