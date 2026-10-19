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

_FETCH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_FETCH_SCRIPT_DIR}/../../.." && pwd)"
source "${_FETCH_SCRIPT_DIR}/build-flags.sh"

echo "--- SWIFT VERSION ---"
swift --version
echo "--- FETCH DEPENDENCIES ---"
# Make a few attempts to fetch the dependencies. Downloads can fail due to
# transient errors and it is better to retry them.
resolve_package "."
echo "--- Initial disk space"
df -h
echo "--- DONE ---"
