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

@testable import GoogleCloudBigQuery

/// JSON fixtures shared by the job, query, and upload tests.
enum JobFixtures {
  /// A `Job` resource.
  static func job(
    id: String = "j",
    project: String = "test-project",
    location: String? = nil,
    state: String = "DONE",
    errorReason: String? = nil,
    configuration: String = #"{"query": {"query": "SELECT 1"}}"#,
    statistics: String? = nil
  ) -> String {
    var reference = #""projectId": "\#(project)", "jobId": "\#(id)""#
    if let location { reference += #", "location": "\#(location)""# }
    var status = #""state": "\#(state)""#
    if let errorReason {
      status +=
        #", "errorResult": {"reason": "\#(errorReason)", "message": "\#(errorReason) happened"}"#
    }
    var json =
      #"{"jobReference": {\#(reference)}, "configuration": \#(configuration), "status": {\#(status)}"#
    if let statistics { json += #", "statistics": \#(statistics)"# }
    return json + "}"
  }

  /// A `GetQueryResultsResponse` or `QueryResponse`.
  static func queryResults(
    id: String? = "j",
    complete: Bool = true,
    schema: Bool = true,
    rows: [String] = [],
    totalRows: Int? = nil,
    pageToken: String? = nil,
    extra: String = ""
  ) -> String {
    var fields = [#""jobComplete": \#(complete)"#]
    if let id {
      fields.append(#""jobReference": {"projectId": "test-project", "jobId": "\#(id)"}"#)
    }
    if schema {
      fields.append(#""schema": {"fields": [{"name": "name", "type": "STRING"}]}"#)
      let cells = rows.map { #"{"f": [{"v": "\#($0)"}]}"# }
      fields.append(#""rows": [\#(cells.joined(separator: ", "))]"#)
    }
    if let totalRows { fields.append(#""totalRows": "\#(totalRows)""#) }
    if let pageToken { fields.append(#""pageToken": "\#(pageToken)""#) }
    if !extra.isEmpty { fields.append(extra) }
    return "{" + fields.joined(separator: ", ") + "}"
  }
}
