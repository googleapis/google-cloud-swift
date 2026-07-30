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
import AsyncHTTPClient
import Testing
@testable import GoogleCloudAuth

@Suite struct STSHandlerTests {
  @Test("Verifies form-urlencoded POST exchange parameters and client authentication headers")
  func exchangeToken() async throws {
    let targetURL = try #require(URL(string: "https://sts.googleapis.com/v1/token"))
    let clientID = "test-client-id"
    let clientSecret = "test-client-secret"

    let expectedResponse = TokenResponse(
      accessToken: "ya29.fake-sts-access-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedResponse = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) async throws in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)
        #expect(request.headers["Content-Type"] == ["application/x-www-form-urlencoded"])

        // HTTP Basic Authentication verifies client credentials formatted as "clientID:clientSecret" encoded in Base64.
        let expectedAuth = "Basic \(Data("\(clientID):\(clientSecret)".utf8).base64EncodedString())"
        #expect(request.headers["Authorization"] == [expectedAuth])

        // Request body verification
        guard let buffer = try await request.body?.collect(upTo: 1024 * 1024) else {
          Issue.record("Request body is empty")
          return HTTPClientResponse(version: .http2, status: .badRequest)
        }
        let bodyString = String(
          data: buffer.getData(at: 0, length: buffer.readableBytes)!,
          encoding: .utf8,
        )!

        // Verify body parameters
        let queryItems = URLComponents(string: "?" + bodyString)?.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        #expect(params["grant_type"] == "urn:ietf:params:oauth:grant-type:token-exchange")
        #expect(params["requested_token_type"] == "urn:ietf:params:oauth:token-type:access_token")
        #expect(params["subject_token"] == "fake-subject-token")
        #expect(params["subject_token_type"] == "urn:ietf:params:oauth:token-type:id_token")
        #expect(params["scope"] == "scope1 scope2")
        #expect(params["audience"] == "test-audience")

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedResponse)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let handler = STSHandler(httpClient: client)

    let request = ExchangeTokenRequest(
      subjectToken: "fake-subject-token",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      audience: "test-audience",
      scopes: ["scope1", "scope2"],
      workforcePoolUserProject: "test-quota-project",
      clientAuthentication: ClientAuthentication(id: clientID, secret: clientSecret)
    )

    let response = try await handler.exchangeToken(
      request: request, url: targetURL, encoding: .urlEncoded)
    #expect(response.accessToken == expectedResponse.accessToken)
    #expect(response.tokenType == expectedResponse.tokenType)
    #expect(response.expiresIn == expectedResponse.expiresIn)
    #expect(response.issuedTokenType == expectedResponse.issuedTokenType)
  }

  @Test("Propagates non-success STS server errors cleanly")
  func exchangeTokenErr() async throws {
    let targetURL = try #require(URL(string: "https://sts.googleapis.com/v1/token"))

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        let errorPayload = """
          {
            "error": "invalid_grant",
            "error_description": "Invalid subject token"
          }
          """
        return
          HTTPClientResponse(
            version: .http2,
            status: .badRequest,
            headers: .init([("Content-Type", "application/json")]),
            body: .bytes(.init(data: Data(errorPayload.utf8))),
          )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let handler = STSHandler(httpClient: client)

    let request = ExchangeTokenRequest(
      subjectToken: "invalid-subject-token",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token"
    )

    await #expect(throws: AuthHTTPError.self) {
      _ = try await handler.exchangeToken(request: request, url: targetURL)
    }
  }

  @Test("Supports JSON payload encoding and custom grant type parameter overrides")
  func exchangeTokenJSONAndCustomGrant() async throws {
    let targetURL = try #require(URL(string: "https://sts.googleapis.com/v1/token"))

    let expectedResponse = TokenResponse(
      accessToken: "ya29.fake-sts-access-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedResponse = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) async throws in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)
        #expect(request.headers["Content-Type"] == ["application/json"])

        guard let bodyData = try await request.body?.collect(upTo: 1024 * 1024) else {
          Issue.record("Request body is empty")
          return HTTPClientResponse(version: .http2, status: .badRequest)
        }

        do {
          let jsonDict = try JSONDecoder().decode([String: String].self, from: bodyData)
          #expect(jsonDict["grant_type"] == "urn:ietf:params:oauth:grant-type:token-exchange")
          #expect(
            jsonDict["requested_token_type"] == "urn:ietf:params:oauth:token-type:access_token")
          #expect(jsonDict["subject_token"] == "fake-subject-token")
          #expect(jsonDict["subject_token_type"] == "urn:ietf:params:oauth:token-type:id_token")
          #expect(jsonDict["options"] == "{\"userProject\":\"test-quota-project\"}")
        } catch {
          Issue.record("Failed to parse JSON body: \(error)")
        }

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedResponse)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let handler = STSHandler(httpClient: client)

    let request = ExchangeTokenRequest(
      subjectToken: "fake-subject-token",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      workforcePoolUserProject: "test-quota-project"
    )

    let response = try await handler.exchangeToken(
      request: request, url: targetURL, encoding: .json)
    #expect(response.accessToken == expectedResponse.accessToken)
  }
}
