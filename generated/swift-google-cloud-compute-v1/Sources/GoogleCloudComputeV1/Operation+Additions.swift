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

    /// Inspects the terminal `Operation` for failure indicators and throws a
    /// `GoogleGax.RequestError.service` if the operation failed.
    ///
    /// Compute Engine operations can report failure in three ways:
    /// 1. Top-level error fields (`error`, `httpErrorStatusCode`, or `httpErrorMessage`).
    /// 2. Per-location VM creation failures in `instancesBulkInsertOperationMetadata`.
    /// 3. Per-location errors in `setCommonInstanceMetadataOperationMetadata`.
    func _detectErrors() throws {
      if self.error != nil || (self.httpErrorStatusCode ?? 0) != 0 || self.httpErrorMessage != nil {
        throw GoogleGax.RequestError.service(self._parseServiceError())
      }

      if let metadata = self.instancesBulkInsertOperationMetadata,
        metadata.perLocationStatus.values.contains(where: { ($0.failedToCreateVmCount ?? 0) > 0 })
      {
        throw GoogleGax.RequestError.service(
          GoogleGax.ServiceError(
            code: .unknown,
            message: "Instances bulk insert operation failed",
            details: (try? GoogleWKT.WKTAny(fromMessage: metadata)).map { [.other($0)] } ?? []
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
            details: (try? GoogleWKT.WKTAny(fromMessage: metadata)).map { [.other($0)] } ?? []
          )
        )
      }
    }

    /// Constructs a `GoogleGax.ServiceError` from the operation's HTTP status,
    /// error message, and structured `error.errors` entries.
    private func _parseServiceError() -> GoogleGax.ServiceError {
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

      // Prefer `httpErrorMessage` when present and non-empty. Otherwise, build a
      // summary from the `code` and `message` fields of each `error.errors` entry
      // before falling back to a generic message.
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
        }.joined(separator: "\n")
        message = formatted.isEmpty ? "Operation failed" : formatted
      } else {
        message = "Operation failed"
      }

      let details = self.error?.errors.flatMap(Self._extractStatusDetails(from:)) ?? []
      return GoogleGax.ServiceError(
        code: code,
        message: message,
        details: details,
        httpStatusCode: httpStatusCode
      )
    }

    /// Extracts `GoogleGax.StatusDetail` values from a single Compute `Operation.Error.Errors` entry.
    ///
    /// Compute Engine's Discovery schema defines its own `ErrorInfo`, `Help`, and
    /// `LocalizedMessage` types inside `Operation.Error.Errors.ErrorDetails`. We convert
    /// those into their standard `GoogleRpc` counterparts so callers can pattern-match on
    /// `.errorInfo`, `.help`, and `.localizedMessage` just like standard gRPC/HTTP errors.
    ///
    /// Compute-specific details (`QuotaExceededInfo` and the enclosing `Operation.Error.Errors`
    /// entry itself, which carries `code`, `location`, and `message`) do not have dedicated
    /// `StatusDetail` enum cases and are packed as `WKTAny` in `.other(...)`.
    private static func _extractStatusDetails(
      from entry: Operation.Error.Errors
    ) -> [GoogleGax.StatusDetail] {
      var details: [GoogleGax.StatusDetail] = []
      for detail in entry.errorDetails {
        if let info = detail.errorInfo {
          details.append(
            .errorInfo(
              GoogleRpc.ErrorInfo().with {
                $0.reason = info.reason ?? ""
                $0.domain = info.domain ?? ""
                // Note: Compute's Discovery schema names this field `metadatas` (plural),
                // whereas `google.rpc.ErrorInfo` names it `metadata`.
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
      // Preserve the raw `Operation.Error.Errors` entry so callers can still inspect
      // Compute-specific fields such as `code`, `location`, and `message`.
      if let packedEntry = try? GoogleWKT.WKTAny(fromMessage: entry) {
        details.append(.other(packedEntry))
      }
      return details
    }
  }

#endif
