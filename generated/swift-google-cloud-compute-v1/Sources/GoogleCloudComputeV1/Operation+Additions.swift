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

#if GlobalOperations || GlobalOrganizationOperations || RegionOperations || ZoneOperations

  @_spi(GoogleCloudInternal) import GoogleGax
  import GoogleWKT
  import GoogleRpc

  extension Operation {
    func _done() -> Swift.Bool {
      if let s = self.status, s == .done {
        return true
      }
      return false
    }

    func _name() -> Swift.String {
      return self.name ?? ""
    }

    func _detectErrors() throws {
      if self.error != nil || (self.httpErrorStatusCode ?? 0) != 0 || self.httpErrorMessage != nil {
        let code: GoogleRpc.Code
        let httpStatusCode: Int?
        if let statusCode = self.httpErrorStatusCode, statusCode != 0 {
          let statusInt = Int(statusCode)
          code = GoogleRpc.Code(httpStatusCode: statusInt)
          httpStatusCode = statusInt
        } else {
          code = .unknown
          httpStatusCode = nil
        }

        let message: Swift.String
        if let httpMessage = self.httpErrorMessage, !httpMessage.isEmpty {
          message = httpMessage
        } else if let errors = self.error?.errors {
          let formatted = errors.compactMap { entry -> Swift.String? in
            let entryCode = (entry.code?.isEmpty == false) ? entry.code : nil
            let entryMessage = (entry.message?.isEmpty == false) ? entry.message : nil
            switch (entryCode, entryMessage) {
            case (let c?, let m?):
              return "\(c): \(m)"
            case (nil, let m?):
              return m
            case (let c?, nil):
              return c
            case (nil, nil):
              return nil
            }
          }.joined(separator: ", ")
          message = formatted.isEmpty ? "Operation failed" : formatted
        } else {
          message = "Operation failed"
        }

        var details: [GoogleGax.StatusDetail] = []
        if let errors = self.error?.errors {
          for entry in errors {
            for detail in entry.errorDetails {
              if let info = detail.errorInfo {
                details.append(
                  .errorInfo(
                    GoogleRpc.ErrorInfo().with {
                      $0.reason = info.reason ?? ""
                      $0.domain = info.domain ?? ""
                      $0.metadata = info.metadatas
                    }
                  )
                )
              }
              if let help = detail.help {
                details.append(
                  .help(
                    GoogleRpc.Help().with {
                      $0.links = help.links.map { link in
                        GoogleRpc.Help.Link().with {
                          $0.description = link.description ?? ""
                          $0.url = link.url ?? ""
                        }
                      }
                    }
                  )
                )
              }
              if let localized = detail.localizedMessage {
                details.append(
                  .localizedMessage(
                    GoogleRpc.LocalizedMessage().with {
                      $0.locale = localized.locale ?? ""
                      $0.message = localized.message ?? ""
                    }
                  )
                )
              }
              if let quota = detail.quotaInfo,
                let packedQuota = try? GoogleWKT.WKTAny(fromMessage: quota)
              {
                details.append(.other(packedQuota))
              }
            }
            if let packedEntry = try? GoogleWKT.WKTAny(fromMessage: entry) {
              details.append(.other(packedEntry))
            }
          }
        }

        throw GoogleGax.RequestError.service(
          GoogleGax.ServiceError(
            code: code,
            message: message,
            details: details,
            httpStatusCode: httpStatusCode
          )
        )
      }

      if let metadata = self.instancesBulkInsertOperationMetadata,
        metadata.perLocationStatus.values.contains(where: { ($0.failedToCreateVmCount ?? 0) > 0 })
      {
        throw GoogleGax.RequestError.service(
          GoogleGax.ServiceError(
            code: .unknown,
            message: "Instances bulk insert operation failed",
            details: [.other(try! GoogleWKT.WKTAny(fromMessage: metadata))]
          )
        )
      }

      if let metadata = self.setCommonInstanceMetadataOperationMetadata,
        metadata.perLocationOperations.values.contains(where: { $0.error != nil })
      {
        throw GoogleGax.RequestError.service(
          GoogleGax.ServiceError(
            code: .unknown,
            message: "Set common instance metadata operation failed",
            details: [.other(try! GoogleWKT.WKTAny(fromMessage: metadata))]
          )
        )
      }
    }
  }

#endif
