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

import DatastoreV1Stub
import GoogleGax
import Testing

@Suite struct DatastoreStubCompilationTests {
  @Test func idempotencyDefaultsMatchSpec() {
    let defaultOptions = GoogleGax.RequestOptions()

    // Idempotent RPCs per Section 3.4: Lookup, RunQuery, RunAggregationQuery, ReserveIds
    #expect(LookupRequest().resolveIdempotency(options: defaultOptions).idempotent == true)
    #expect(RunQueryRequest().resolveIdempotency(options: defaultOptions).idempotent == true)
    #expect(
      RunAggregationQueryRequest().resolveIdempotency(options: defaultOptions).idempotent == true)
    #expect(ReserveIdsRequest().resolveIdempotency(options: defaultOptions).idempotent == true)

    // Non-idempotent RPCs per Section 3.4: BeginTransaction, Commit, Rollback, AllocateIds
    #expect(
      BeginTransactionRequest().resolveIdempotency(options: defaultOptions).idempotent == false)
    #expect(CommitRequest().resolveIdempotency(options: defaultOptions).idempotent == false)
    #expect(RollbackRequest().resolveIdempotency(options: defaultOptions).idempotent == false)
    #expect(AllocateIdsRequest().resolveIdempotency(options: defaultOptions).idempotent == false)
  }

  @Test func idempotencyCallerOverrideTakesPrecedence() {
    let forceFalse = GoogleGax.RequestOptions().with { $0.idempotent = false }
    let forceTrue = GoogleGax.RequestOptions().with { $0.idempotent = true }

    #expect(LookupRequest().resolveIdempotency(options: forceFalse).idempotent == false)
    #expect(CommitRequest().resolveIdempotency(options: forceTrue).idempotent == true)
  }
}
