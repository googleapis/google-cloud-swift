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
import Testing

// An empty test-suite to suppress unused dependency warnings.
//
// We want to generate documentation for the UserGuide package from the top-level directory. Without
// a test or other target using the package we get an annoying warning:
//     `dependency 'guide' is not used by any target'
@Suite struct UserGuide {}
