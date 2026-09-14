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

#include "CGoogleCloudGaxCRC32C.h"

#include <string.h>

#if defined(__x86_64__) || defined(_M_X64)
#if defined(__GNUC__) || defined(__clang__)
#include <cpuid.h>
#endif

bool googleCloudGax_crc32c_hw_available(void) {
#if defined(__has_builtin)
#if __has_builtin(__builtin_cpu_supports)
  return __builtin_cpu_supports("sse4.2") != 0;
#endif
#endif
#if defined(__GNUC__) || defined(__clang__)
  unsigned int eax = 0, ebx = 0, ecx = 0, edx = 0;
  if (__get_cpuid(1, &eax, &ebx, &ecx, &edx)) {
    return (ecx & (1 << 20)) != 0;
  }
  return false;
#elif defined(_MSC_VER)
  int info[4] = {0};
  __cpuid(info, 1);
  return (info[2] & (1 << 20)) != 0;
#else
  return false;
#endif
}

#if defined(__clang__) || defined(__GNUC__)
__attribute__((target("sse4.2")))
#endif
uint32_t googleCloudGax_crc32c_hw(uint32_t crc, const uint8_t* data,
                                  size_t len) {
  if (data == NULL || len == 0) {
    return crc;
  }
  while (len > 0 && ((uintptr_t)data & 7) != 0) {
    crc = (uint32_t)__builtin_ia32_crc32qi((int)crc, *data++);
    len--;
  }
  while (len >= 32) {
    uint64_t v0, v1, v2, v3;
    memcpy(&v0, data, 8);
    memcpy(&v1, data + 8, 8);
    memcpy(&v2, data + 16, 8);
    memcpy(&v3, data + 24, 8);
    crc = (uint32_t)__builtin_ia32_crc32di(crc, v0);
    crc = (uint32_t)__builtin_ia32_crc32di(crc, v1);
    crc = (uint32_t)__builtin_ia32_crc32di(crc, v2);
    crc = (uint32_t)__builtin_ia32_crc32di(crc, v3);
    data += 32;
    len -= 32;
  }
  while (len >= 8) {
    uint64_t v;
    memcpy(&v, data, 8);
    crc = (uint32_t)__builtin_ia32_crc32di(crc, v);
    data += 8;
    len -= 8;
  }
  if (len >= 4) {
    uint32_t v;
    memcpy(&v, data, 4);
    crc = (uint32_t)__builtin_ia32_crc32si(crc, (int)v);
    data += 4;
    len -= 4;
  }
  if (len >= 2) {
    uint16_t v;
    memcpy(&v, data, 2);
    crc = (uint32_t)__builtin_ia32_crc32hi(crc, (short)v);
    data += 2;
    len -= 2;
  }
  if (len >= 1) {
    crc = (uint32_t)__builtin_ia32_crc32qi((int)crc, *data++);
    len--;
  }
  return crc;
}

#elif defined(__aarch64__) || defined(_M_ARM64) || defined(__arm64__)
#if defined(__linux__)
#include <sys/auxv.h>
#ifndef HWCAP_CRC32
#define HWCAP_CRC32 (1 << 7)
#endif
#ifndef AT_HWCAP
#define AT_HWCAP 16
#endif
#elif defined(__APPLE__)
#include <sys/sysctl.h>
#elif defined(_WIN32)
#include <windows.h>
#endif

bool googleCloudGax_crc32c_hw_available(void) {
#if defined(__APPLE__)
  int val = 0;
  size_t size = sizeof(val);
  if (sysctlbyname("hw.optional.armv8_crc32", &val, &size, NULL, 0) == 0) {
    return val != 0;
  }
  return true;
#elif defined(__linux__)
  return (getauxval(AT_HWCAP) & HWCAP_CRC32) != 0;
#elif defined(_WIN32) && defined(PF_ARM_V8_CRC32_INSTRUCTIONS_AVAILABLE)
  return IsProcessorFeaturePresent(PF_ARM_V8_CRC32_INSTRUCTIONS_AVAILABLE) != 0;
#else
  return false;
#endif
}

#if defined(__clang__)
__attribute__((target("crc")))
#elif defined(__GNUC__)
__attribute__((target("+crc")))
#endif
uint32_t googleCloudGax_crc32c_hw(uint32_t crc, const uint8_t* data,
                                  size_t len) {
  if (data == NULL || len == 0) {
    return crc;
  }
  while (len > 0 && ((uintptr_t)data & 7) != 0) {
    crc = __builtin_arm_crc32cb(crc, *data++);
    len--;
  }
  while (len >= 32) {
    uint64_t v0, v1, v2, v3;
    memcpy(&v0, data, 8);
    memcpy(&v1, data + 8, 8);
    memcpy(&v2, data + 16, 8);
    memcpy(&v3, data + 24, 8);
    crc = __builtin_arm_crc32cd(crc, v0);
    crc = __builtin_arm_crc32cd(crc, v1);
    crc = __builtin_arm_crc32cd(crc, v2);
    crc = __builtin_arm_crc32cd(crc, v3);
    data += 32;
    len -= 32;
  }
  while (len >= 8) {
    uint64_t v;
    memcpy(&v, data, 8);
    crc = __builtin_arm_crc32cd(crc, v);
    data += 8;
    len -= 8;
  }
  if (len >= 4) {
    uint32_t v;
    memcpy(&v, data, 4);
    crc = __builtin_arm_crc32cw(crc, v);
    data += 4;
    len -= 4;
  }
  if (len >= 2) {
    uint16_t v;
    memcpy(&v, data, 2);
    crc = __builtin_arm_crc32ch(crc, v);
    data += 2;
    len -= 2;
  }
  if (len >= 1) {
    crc = __builtin_arm_crc32cb(crc, *data++);
    len--;
  }
  return crc;
}

#else
bool googleCloudGax_crc32c_hw_available(void) { return false; }

uint32_t googleCloudGax_crc32c_hw(uint32_t crc, const uint8_t* data,
                                  size_t len) {
  (void)data;
  (void)len;
  return crc;
}
#endif
