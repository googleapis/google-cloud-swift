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

import GoogleCloudWkt

@Suite struct FieldsRecursion {
  @Test(
    "Recursion fields deserialize",
    arguments: [
      // Empty case
      (#"{}"#, MessageWithRecursion()),
      // Deep recursive chain
      (
        """
        {
          "singular": {
            "level1": {
              "recurse": {
                "singular": {
                  "side": {
                    "value": "depth-3"
                  }
                }
              }
            }
          }
        }
        """,
        MessageWithRecursion().with {
          $0.singular = Recursive(
            value: MessageWithRecursion.Level0().with {
              $0.level1 = Recursive(
                value: MessageWithRecursion.Level1().with {
                  $0.recurse = Recursive(
                    value: MessageWithRecursion().with {
                      $0.singular = Recursive(
                        value: MessageWithRecursion.Level0().with {
                          $0.side = MessageWithRecursion.NonRecursive().with {
                            $0.value = "depth-3"
                          }
                        })
                    })
                })
            })
        }
      ),
      // Optional recursive field
      (
        #"{"optional": {"side": {"value": "optional-side"}}}"#,
        MessageWithRecursion().with {
          $0.optional = Recursive(
            value: MessageWithRecursion.Level0().with {
              $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "optional-side" }
            })
        }
      ),
      // Repeated recursive field
      (
        #"{"repeated": [{"side": {"value": "side-1"}}, {"side": {"value": "side-2"}}]}"#,
        MessageWithRecursion().with {
          $0.repeated = [
            MessageWithRecursion.Level0().with {
              $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "side-1" }
            },
            MessageWithRecursion.Level0().with {
              $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "side-2" }
            },
          ]
        }
      ),
      // Map recursive field
      (
        #"{"map": {"key1": {"side": {"value": "side-1"}}, "key2": {"side": {"value": "side-2"}}}}"#,
        MessageWithRecursion().with {
          $0.map = [
            "key1": MessageWithRecursion.Level0().with {
              $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "side-1" }
            },
            "key2": MessageWithRecursion.Level0().with {
              $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "side-2" }
            },
          ]
        }
      ),
    ])
  func deserialize(input: String, want: MessageWithRecursion) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(MessageWithRecursion.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test func testRoundtripSerialization() throws {
    let input = MessageWithRecursion().with {
      $0.singular = Recursive(
        value: MessageWithRecursion.Level0().with {
          $0.level1 = Recursive(
            value: MessageWithRecursion.Level1().with {
              $0.recurse = Recursive(
                value: MessageWithRecursion().with {
                  $0.singular = Recursive(
                    value: MessageWithRecursion.Level0().with {
                      $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "roundtrip" }
                    })
                })
            })
        })
      $0.optional = Recursive(
        value: MessageWithRecursion.Level0().with {
          $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "optional-roundtrip" }
        })
      $0.repeated = [
        MessageWithRecursion.Level0().with {
          $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "repeated-roundtrip" }
        }
      ]
      $0.map = [
        "mapkey": MessageWithRecursion.Level0().with {
          $0.side = MessageWithRecursion.NonRecursive().with { $0.value = "map-roundtrip" }
        }
      ]
    }

    let data = try JSONEncoder().encode(input)
    let decoded = try _ProtoJSONDecoder().decode(MessageWithRecursion.self, from: data)
    #expect(decoded == input)
  }
}
