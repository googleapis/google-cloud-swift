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

import StorageW1R3
import Testing

@Suite struct ResumableModeOptionTests {
  @Test func parsesStreamingVariants() {
    #expect(ResumableModeOption(argument: "streaming") == .streaming)
    #expect(ResumableModeOption(argument: "STREAMING") == .streaming)
  }

  @Test func parsesChunkedVariants() {
    #expect(ResumableModeOption(argument: "chunked") == .chunked)
    #expect(ResumableModeOption(argument: "CHUNKED") == .chunked)
  }

  @Test func parsesRandomVariants() {
    #expect(ResumableModeOption(argument: "random") == .random)
    #expect(ResumableModeOption(argument: "RANDOM") == .random)
  }

  @Test func rejectsInvalidArguments() {
    #expect(ResumableModeOption(argument: "") == nil)
    #expect(ResumableModeOption(argument: "fast") == nil)
    #expect(ResumableModeOption(argument: "1") == nil)
  }
}
