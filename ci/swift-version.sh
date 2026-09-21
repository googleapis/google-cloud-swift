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

# Reports whether the Swift toolchain honors `@diagnose`.
#
# The generated code carries the deprecations from the source specification
# into the Swift API, so customers are warned when they use them. It must
# still read, write and convert those declarations, which warns in turn.
#
# Swift 6.4 introduced `@diagnose` (SE-0522), and the generator uses it to
# silence exactly those warnings. Swift 6.2 and 6.3 skip the
# `#if hasAttribute(diagnose)` blocks and keep reporting them, so builds with
# those toolchains must demote the diagnostic. Otherwise
# `-Xswiftc -warnings-as-errors` fails.
#
# Demoting it unconditionally would also hide genuine use of deprecated APIs in
# the hand-written code, which is why this is version conditional. Do not
# reinstate the flags for every toolchain.
swift_supports_diagnose() {
    local version major minor
    # The minor version is optional: every released toolchain prints `x.y`, but
    # a hypothetical `Swift version 7` must not silently parse as "too old".
    # Trimming to the first match in the shell avoids `head -1` closing the
    # pipe, which would fail under `set -o pipefail`.
    version="$(swift --version 2>/dev/null |
        sed -n 's/.*Swift version \([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p')"
    version="${version%%$'\n'*}"
    [[ -n "${version}" ]] || return 1
    major="${version%%.*}"
    minor="${version#*.}"
    minor="${minor%%.*}"
    [[ "${minor}" == "${version}" ]] && minor=0
    if ((major > 6 || (major == 6 && minor >= 4))); then
        return 0
    fi
    return 1
}
