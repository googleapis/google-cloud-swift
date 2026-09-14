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

#ifndef C_GOOGLE_CLOUD_GAX_CRC32C_H
#define C_GOOGLE_CLOUD_GAX_CRC32C_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns true if hardware-accelerated CRC32C is supported by the current host
/// CPU.
bool googleCloudGax_crc32c_hw_available(void);

/// Computes an updated CRC32C checksum over `data` of length `len` using CPU
/// instructions. Must only be called if `googleCloudGax_crc32c_hw_available()`
/// returns true.
///
/// @param crc The running inverted CRC value (seed ^ 0xFFFFFFFF).
/// @param data Pointer to input buffer.
/// @param len Number of bytes.
/// @return The updated inverted CRC value.
uint32_t googleCloudGax_crc32c_hw(uint32_t crc, const void* data,
                                  size_t len);

#ifdef __cplusplus
}
#endif

#endif /* C_GOOGLE_CLOUD_GAX_CRC32C_H */
