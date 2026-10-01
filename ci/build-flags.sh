#!/usr/bin/env bash
#
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

_BUILD_FLAGS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_BUILD_FLAGS_SCRIPT_DIR}/.." && pwd)}"

build_flags=(
    --build-system native
    -Xswiftc -warnings-as-errors
    --scratch-path "${GOOGLE_CLOUD_SWIFT_SCRATCH_PATH:-${REPO_ROOT}/.build-cache}"
)

# Swift < 6.4 cannot honor the `@diagnose` attributes in the generated code.
# The remaining builds stay strict.
source "${_BUILD_FLAGS_SCRIPT_DIR}/swift-version.sh"
if ! swift_supports_diagnose; then
    build_flags+=(-Xswiftc -Wwarning -Xswiftc DeprecatedDeclaration)
fi

source "${_BUILD_FLAGS_SCRIPT_DIR}/glinux-flags.sh"
add_glinux_flags

flags=("${build_flags[@]}")
