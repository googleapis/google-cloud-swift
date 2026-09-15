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

# Extra build flags for workstations that are not usr-merged.
#
# Such systems have a real `/lib` directory holding its own GCC installation
# tree, separate from `/usr/lib/gcc`. SwiftPM's default build system compiles
# C and C++ targets with `--sysroot /`. Clang then derives the C++ standard
# library include path relative to whichever GCC installation it finds first,
# which is the one under `/lib/gcc/...`, and ends up looking in
# `/include/c++/<version>`. That directory does not exist, so the libstdc++
# headers are silently dropped from the include search path and every C++
# target fails with "'memory' file not found". In practice this breaks the
# BoringSSL targets pulled in by `swift-nio-ssl` and `swift-crypto`.
#
# Pointing clang at the real GCC installation prefix avoids the problem. Note
# that this does not change which compiler is used: clang still compiles the
# code, it only consults the GCC installation under `/usr` to locate the C++
# standard library.
#
# Google workstations (glinux) are the known case, so gate on that rather than
# applying the flags everywhere.

add_glinux_flags() {
    [[ -r /etc/os-release ]] || return 0
    grep -q glinux /etc/os-release || return 0
    flags+=(-Xcc --gcc-toolchain=/usr -Xcxx --gcc-toolchain=/usr)
}
