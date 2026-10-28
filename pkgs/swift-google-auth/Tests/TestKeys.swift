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

enum TestKeys {
  /// A 2048-bit PKCS#8 RSA private key for deterministic unit testing.
  static let validPKCS8PEM = """
    -----BEGIN PRIVATE KEY-----
    MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCcPLcw48+yRt5f
    CXKKIHnvNZHuiriD1nrP17OQpHDTkWTq5+ynEDusFXkauFCbUJHrSOTokXDFHZlu
    3HRWM2tRxg8IZODpExgKtqYhS5peJ5iY8Q6Ur1+WvhBln4M5VMtjW2YiN+zrkiCY
    p04KygGo1UZ92ocBpiSOSkqqXoQj+AqBHRGLK3GPmCLqxgzMk2VGGmpTU1mTLN6O
    2CtFkqPmcadypG0vlEbkUYunQud/MhyDb6ArhwrJQa6X6iOvbar7yxaOy0xix/Xk
    s/hcMyVySrjv2/K/LbaVuEOhhseL/gcI0bP8qvn0dZ8c5l9KcdX/fr6aFcrTcqlu
    u4wdNMv5AgMBAAECggEAMTB2dqiK2DSyx1Yony9ZZIRHtUQskqmA0hY13SjAswOY
    M9MgMXsNZoD+N3jnO/cScfLpywUbbZwDliFHaWpX9A945Sopm4gc7iaSSHJOoC00
    QJbIgexzGnktnWkqve6h+F6q2cQkzggcRiOKkSAHhLndLzuRfOXrpXbjah9G2DG9
    5CIWjY/VdZQrwWrmzkY2WJVoW52Cfj5TBmCbpNk0Rdbv5q1957TGscQKELxp3wt9
    ash4KGg2NlAP/fjRLs+X+9/dSxV8RHnovxPnXVy5XDcGisSX8rHjsjV3rZTs2Nls
    ug1kJcAgg9i51wgsvE8Fu3lzLC3ewYmpilI5O8XA9wKBgQDafd7Hu7LMP9UisX4y
    FTuxLZUoeN7erutAWzO8deyTFM/BW1blzQBHCAUA1cMPftdFaFPfgBaz6CkikhMv
    0ySPjyyKsVDVObKCKo0XxISrdiuqE1K62Yn/gfyh8ZdEv+qkJvz1XaBb8DrlbpqK
    EAXeLsckPV6lUqcv7BhojdeTmwKBgQC3Duy9rw8yxWpvfRubsuT7CQ7p6YTM1KAx
    egNiKBGx6sj3KWGVcJPCPZkaD1+XJO6zhOqyL5/syviFTDuyEIWYBaY0odJwb7Vg
    KVXdBa5UwI6DYmsZAAAOP1wywwQrYuqwuVhy3+09iKPkGOJ4I32Kw5HYvJ79qL19
    sRE0/e3p+wKBgFG/8MAYuaB0bcHKWWZRzYDQhlObTgBRwFHXDfeAw+CQU9+L1mqr
    FmR9WqniUVaV5ePhUih424W64tE9iJJHVRGlx0upZo4xRVowo5P2ApHI6DN9gWHK
    DTkdoLHTG/8sM5XxxInl2x8rNk4r4QSxVBC6veYQVD5VO5rRopxUHgnrAoGAeHZq
    1hw4PSnqc7l5jIk54/S/CrDwAja9wDFRvqstkc42N2fU3pl5sq4EbUDGn9je9+W0
    6FMsw4+B4X4cHn5+216EVEhVCkaIreIlrc/KO92HKvB+F7KHVtjdHE53FPIADRG7
    IcU4AnFDoJu7lGGOgN1Xwa/GVJhRMkBuWVfs0zcCgYEAlP9KCxjRXtcJEnB81uHx
    sjUYPwyP5KbyYnl9LRbqfvZPIMgV2BIl+wOLUhSFYpxsDK3Otf/SyKm3qkifT4E2
    TEsACTOH4L3aH53EIDbugMPAyMbsTZfR4EK2zGi1QOl0hjZ+kUSNcPlDAUK9vXfF
    1ARUsyX+ffQ++dMyCItdcEg=
    -----END PRIVATE KEY-----
    """

  /// `validPKCS8PEM` with newlines escaped (`\n` -> `\\n`) for embedding in JSON literals.
  static let escapedPKCS8PEM = validPKCS8PEM.replacingOccurrences(of: "\n", with: "\\n")
}
