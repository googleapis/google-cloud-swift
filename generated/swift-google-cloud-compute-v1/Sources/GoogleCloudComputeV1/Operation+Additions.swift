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

  import GoogleGax
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
        throw GoogleGax.RequestError.service(
          GoogleGax.ServiceError(
            code: GoogleRpc.Code(intValue: Int(self.httpErrorStatusCode ?? 0)),
            message: self.httpErrorMessage ?? "Operation failed",
            details: self.error?.errors.compactMap { try? GoogleWKT.WKTAny(fromMessage: $0) }.map {
              .other($0)
            } ?? []
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
