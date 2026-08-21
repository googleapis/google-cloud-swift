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

set -euo pipefail

echo "--- SWIFT VERSION ---"
swift --version
echo "--- VERSIONS ---"

flags=(
    -Xswiftc -warnings-as-errors
    -Xswiftc -Wwarning
    -Xswiftc DeprecatedDeclaration
    --scratch-path "/workspace/.build-cache"
    --build-path   "/workspace/.build"
)
if [[ -z "${PROJECT_ID:-}" ]]; then
    echo "✗ missing PROJECT_ID environment variable"
    exit 1
fi
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export GOOGLE_CLOUD_SWIFT_TEST_SERVICE_ACCOUNT=swift-sdk-test@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com
export GOOGLE_CLOUD_SWIFT_TEST_BUCKET=${GOOGLE_CLOUD_PROJECT}-test-bucket

errors=0
count=1
echo "--- Running top-level integration tests ---"
if swift test "${flags[@]}" --quiet; then
    echo; echo "✓ integration tests passed"
else
    echo; echo "✗ integration tests failed"
    errors=$((errors + 1))
fi

for dir in packages/*; do
    [[ -f "${dir}/Package.swift" ]] || continue
    [[ -d "${dir}/Tests" ]] || continue
    count=$((count + 1))
    echo "--- Running ${dir} integration tests ---"
    if swift test "${flags[@]}" --quiet --package-path "${dir}" --enable-all-traits; then
        echo; echo "✓ ${dir} passed"
    else
        echo; echo "✗ ${dir} failed"
        errors=$((errors + 1))
    fi
done

echo; echo; echo "${count} local package(s) tested, ${errors} failure(s)."

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
