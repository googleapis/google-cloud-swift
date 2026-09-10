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
@_spi(GoogleCloudInternal) import GoogleCloudGax
import Testing

@Suite struct CRC32CTests {
  @Test(arguments: [
    ("", UInt32(0)),
    (hello, helloCRC32C),
    (spanish, spanishCRC32C),
    (zebras, zebrasCRC32C),
    (fox, foxCRC32C),
    (gettysburg, gettysburgCRC32C),
  ])
  func compute(input: String, want: UInt32) {
    let got = _CRC32C.compute(Data(input.utf8))
    #expect(want == got)
  }

  @Test func update() {
    var checksum = _CRC32C()
    checksum.update(Data("Hello".utf8))
    checksum.update(Data(" ".utf8))
    checksum.update(Data("World".utf8))
    let got = checksum.finalize()
    #expect(helloCRC32C == got)
  }
}

// We can get these magic value using:
//   gcloud storage hash --skip-md5 file.txt
// And then manipulate the output with your favorite base64 decoder.
let helloCRC32C: UInt32 = 0x691daa2f  // 0xaa2f691d
let hello = "Hello World"

let spanishCRC32C: UInt32 = 0xc72af3d3
let spanish =
  "Benjamín pidió una bebida de kiwi y fresa. Noé, sin vergüenza, la más exquisita champaña del menú"

let zebrasCRC32C: UInt32 = 0xf5eb161d
let zebras = "how vexingly quick daft zebras jump"

let foxCRC32C: UInt32 = 0x3c18f4d6
let fox = "the quick brown fox jumps over the lazy dog"

let gettysburgCRC32C: UInt32 = 0x802a36d6
let gettysburg = """
  Four score and seven years ago our fathers brought forth on this continent a new
  nation, conceived in liberty, and dedicated to the proposition that all men are
  created equal.

  Now we are engaged in a great civil war, testing whether that nation, or any
  nation so conceived and so dedicated, can long endure. We are met on a great
  battlefield of that war. We have come to dedicate a portion of that field as a
  final resting place for those who here gave their lives that that nation might
  live. It is altogether fitting and proper that we should do this.

  But in a larger sense we cannot dedicate, we cannot consecrate, we cannot hallow
  this ground. The brave men, living and dead, who struggled here have consecrated
  it, far above our poor power to add or detract. The world will little note, nor
  long remember, what we say here, but it can never forget what they did here. It
  is for us the living, rather, to be dedicated here to the unfinished work which
  they who fought here have thus far so nobly advanced. It is rather for us to be
  here dedicated to the great task remaining before us,that from these honored
  dead we take increased devotion to that cause for which they gave the last full
  measure of devotion, that we here highly resolve that these dead shall not have
  died in vain, that this nation, under God, shall have a new birth of freedom,
  and that government of the people, by the people, for the people, shall not
  perish from the earth.

  """
