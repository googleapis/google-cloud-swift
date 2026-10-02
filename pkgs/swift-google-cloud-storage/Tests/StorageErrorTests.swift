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
@testable import GoogleCloudStorage
import GoogleGax
import Testing

@Suite struct ReadObjectErrorTests {
  @Test func checksumMismatch() {
    let error = ReadObjectError.checksumMismatch(
      expected: "abc",
      actual: "xyz",
      algorithm: "crc32c"
    )
    #expect(error.description == "Checksum mismatch using crc32c: expected 'abc', got 'xyz'")
    #expect(
      error.debugDescription
        == "ReadObjectError.checksumMismatch(expected: \"abc\", actual: \"xyz\", algorithm: \"crc32c\")"
    )
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason == "The downloaded data checksum did not match the expected value."
    )
    #expect(error.recoverySuggestion == "Verify data integrity or retry the download.")
  }

  @Test func invalidRangeHeader() {
    let error = ReadObjectError.invalidRangeHeader("bytes=invalid")
    #expect(error.description == "Invalid range header: 'bytes=invalid'")
    #expect(error.debugDescription == "ReadObjectError.invalidRangeHeader(\"bytes=invalid\")")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The range header returned by Cloud Storage is invalid or malformed."
    )
    #expect(error.recoverySuggestion == nil)
  }

  @Test func resumeFailed() {
    let underlying = RequestError.service(
      ServiceError(
        code: .unavailable,
        message: "Service Unavailable",
        httpStatusCode: 503
      )
    )
    let error = ReadObjectError.resumeFailed(bytesReceived: 1024, underlyingError: underlying)
    #expect(
      error.description
        == "Resume download failed after receiving 1024 bytes: \(underlying)"
    )
    #expect(
      error.debugDescription
        == "ReadObjectError.resumeFailed(bytesReceived: 1024, underlyingError: \(String(reflecting: underlying)))"
    )
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "Transparent download auto-resumption failed after a network interruption."
    )
    #expect(error.recoverySuggestion == "Retry the download from the beginning.")
  }

  @Test func unexpectedServerResponse() {
    let error = ReadObjectError.unexpectedServerResponse(statusCode: 418, message: "Teapot")
    #expect(error.description == "Unexpected server response with status code 418: Teapot")
    #expect(
      error.debugDescription
        == "ReadObjectError.unexpectedServerResponse(statusCode: 418, message: \"Teapot\")"
    )
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "Cloud Storage returned an unexpected HTTP status code during download."
    )
    #expect(error.recoverySuggestion == nil)
  }

  @Test func requestError() {
    let requestError = RequestError.service(
      ServiceError(
        code: .notFound,
        message: "Not Found",
        httpStatusCode: 404
      )
    )
    let error = ReadObjectError.requestError(requestError)
    #expect(error.description == "\(requestError)")
    #expect(
      error.debugDescription
        == "ReadObjectError.requestError(\(String(reflecting: requestError)))"
    )
    #expect(
      error.localizedDescription
        == ((requestError as? LocalizedError)?.errorDescription ?? error.description)
    )
    #expect(error.failureReason == (requestError as? LocalizedError)?.failureReason)
    #expect(error.recoverySuggestion == (requestError as? LocalizedError)?.recoverySuggestion)
  }
}

@Suite struct WriteObjectErrorTests {
  @Test func unexpectedServerResponse() {
    let error = WriteObjectError.unexpectedServerResponse(statusCode: 500, message: "Server Error")
    #expect(error.description == "Unexpected server response with status code 500: Server Error")
    #expect(
      error.debugDescription
        == "WriteObjectError.unexpectedServerResponse(statusCode: 500, message: \"Server Error\")"
    )
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "Cloud Storage returned an unexpected HTTP status code or error response during write."
    )
    #expect(error.recoverySuggestion == nil)
  }

  @Test func internalError() {
    let error = WriteObjectError.internalError("buffer overflow")
    #expect(error.description == "Internal error in upload library: buffer overflow")
    #expect(error.debugDescription == "WriteObjectError.internalError(\"buffer overflow\")")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason == "An internal error occurred in the upload library."
    )
    #expect(error.recoverySuggestion == nil)
  }

  @Test func invalidRangeHeader() {
    let error = WriteObjectError.invalidRangeHeader("invalid")
    #expect(error.description == "Invalid range header: 'invalid'")
    #expect(error.debugDescription == "WriteObjectError.invalidRangeHeader(\"invalid\")")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The range header returned by Cloud Storage is invalid or malformed."
    )
    #expect(error.recoverySuggestion == nil)
  }

  @Test func requestError() {
    let requestError = RequestError.service(
      ServiceError(
        code: .unavailable,
        message: "Unavailable",
        httpStatusCode: 503
      )
    )
    let error = WriteObjectError.requestError(requestError)
    #expect(error.description == "\(requestError)")
    #expect(
      error.debugDescription
        == "WriteObjectError.requestError(\(String(reflecting: requestError)))"
    )
    #expect(
      error.localizedDescription
        == ((requestError as? LocalizedError)?.errorDescription ?? error.description)
    )
    #expect(error.failureReason == (requestError as? LocalizedError)?.failureReason)
    #expect(error.recoverySuggestion == (requestError as? LocalizedError)?.recoverySuggestion)
  }

  @Test func sourceError() {
    struct TestSourceError: Error, CustomStringConvertible {
      var description: String { "custom source failure" }
    }
    let error = WriteObjectError.sourceError(TestSourceError())
    #expect(error.description == "Source error: custom source failure")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "An error occurred while reading from or seeking the write object source."
    )
    #expect(error.recoverySuggestion == nil)
  }

  @Test func fromSourceError() {
    let writeError = WriteObjectError.internalError("already write error")
    let resolved = WriteObjectError.fromSourceError(writeError)
    switch resolved {
    case .internalError(let msg):
      #expect(msg == "already write error")
    default:
      Issue.record("Expected internalError")
    }

    struct GenericErr: Error {}
    let fromGeneric = WriteObjectError.fromSourceError(GenericErr())
    switch fromGeneric {
    case .sourceError(let err):
      #expect(err is GenericErr)
    default:
      Issue.record("Expected sourceError")
    }
  }
}

@Suite struct CustomerEncryptionKeyErrorTests {
  @Test func invalidKeyLength() {
    let error = CustomerEncryptionKeyError.invalidKeyLength(actual: 16, expected: 32)
    #expect(
      error.description
        == "Invalid customer encryption key length: got 16 bytes, expected 32 bytes."
    )
    #expect(
      error.debugDescription
        == "CustomerEncryptionKeyError.invalidKeyLength(actual: 16, expected: 32)"
    )
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The key length in bytes does not match the expected length required by the algorithm."
    )
    #expect(error.recoverySuggestion == "Provide a 256-bit (32-byte) AES key.")
  }

  @Test func invalidBase64Key() {
    let error = CustomerEncryptionKeyError.invalidBase64Key
    #expect(
      error.description
        == "Customer encryption key is not a valid base64-encoded string."
    )
    #expect(error.debugDescription == "CustomerEncryptionKeyError.invalidBase64Key")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The provided key string is not a valid Base64-encoded string."
    )
    #expect(error.recoverySuggestion == "Ensure the key is encoded as standard Base64.")
  }
}

@Suite struct WriteObjectSourceErrorTests {
  @Test func offsetOutOfBounds() {
    let error = WriteObjectSourceError.offsetOutOfBounds(offset: 200, size: 100)
    #expect(error.description == "Seek offset out of bounds: offset 200 exceeds size 100")
    #expect(
      error.debugDescription
        == "WriteObjectSourceError.offsetOutOfBounds(offset: 200, size: 100)"
    )
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The requested seek offset exceeds the size of the source."
    )
    #expect(error.recoverySuggestion == nil)
  }

  @Test func readFailed() {
    struct TestUnderlyingError: Error, CustomStringConvertible {
      var description: String { "disk read failure" }
    }
    let error = WriteObjectSourceError.readFailed(underlyingError: TestUnderlyingError())
    #expect(error.description == "Read from source failed: disk read failure")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason == "Reading from the underlying data source failed."
    )
    #expect(error.recoverySuggestion == nil)
  }
}
