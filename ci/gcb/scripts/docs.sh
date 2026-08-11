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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "--- SWIFT VERSION ---"
swift --version
echo "--- Initial disk space"
df -h
echo
echo

errors=0
count=0

flags=(
    --warnings-as-errors
)
targets=(
    GoogleCloudWkt
    GoogleCloudAuth
    GoogleCloudGax
    GoogleCloudSecretManagerV1
)
echo "--- Building ${#targets[@]} targets"
for target in "${targets[@]}"; do
    count=$((count + 1))

    echo; echo "================ Building ${target} ================"
    if swift package generate-documentation "${flags[@]}" --target "${target}"; then
        echo "✓ ${target} built successfully"
    else
        echo; echo "✗ ${target} failed to build"
        errors=$((errors + 1))
        continue
    fi
done

# TODO(https://github.com/googleapis/google-cloud-swift/issues/308) - the xref links need fixing
# after that we can merge this to the main loop
echo; echo "================ Building GoogleCloudStorage ================"
count=$((count + 1))
if swift package generate-documentation  --target "GoogleCloudStorage"; then
    echo "✓ GoogleCloudStorage built successfully"
else
    echo; echo "✗ GoogleCloudStorage failed to build"
    errors=$((errors + 1))
fi

echo; echo; echo "${count} local targets(s) built, ${errors} failure(s)."
echo "--- Remaining disk space"
df -h

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
