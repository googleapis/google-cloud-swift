# BigQuery Java test baseline for the Swift port

Owner: `baseline` worker. Status: catalog complete; the **Swift test** columns are filled in during verification.

This document catalogs the tests of the reference Java client
(`google-cloud-java/java-bigquery/google-cloud-bigquery`, test root
`src/test/java/com/google/cloud/bigquery/`) and classifies each tested
behavior for the Swift port `pkgs/swift-google-cloud-bigquery` (module
`GoogleCloudBigQuery`). It is the coverage contract for design decision D5:
Swift unit tests must cover every `PORT`/`ADAPT` unit row, and Swift
integration tests must cover every `PORT`/`ADAPT` IT row.

## 1. How to read this document

### 1.1 IDs and citations

- **Unit rows** are grouped by *behavior*, not by assertion; one row may
  cover several Java test methods. IDs are `U.<JavaClassMinusTest>.<NN>`
  (for example `U.BigQueryImpl.27`). Every one of the 800 Java unit
  `@Test` methods appears in exactly one row (checked mechanically).
- **IT rows** are one per active Java integration test method, numbered
  `IT-001` ... `IT-214` in file order (`ITBigQueryTest`,
  `ITHighPrecisionTimestamp`, `ITNightlyBigQueryTest`, `ITOpenTelemetryTest`,
  `ITRemoteUDFTest`).
- IDs are stable. Swift tests should reference them in a comment, for
  example `// Baseline: U.BigQueryImpl.27, IT-104`, so that the mapping can
  be regenerated with a search.
- Line ranges (`L<start>-L<end>`) are relative to the Java test file linked in
  each section header and span the `@Test` annotation to the closing brace.

### 1.2 Classification

| Class | Meaning |
|---|---|
| `PORT` | The Swift port must have an equivalent test for this behavior (wire format, request construction, defaults, retries, error mapping, 404 semantics, paging, query routing, value parsing). |
| `ADAPT` | Port the behavior with a Swift-idiomatic shape; the Notes column says how (for example builders to struct initializers, Mockito RPC mocks to a fake HTTP transport, `Page` to `AsyncSequence`, varargs options to an options struct, live-object methods to client methods). |
| `N/A` | Java-specific mechanics with no Swift equivalent: `Serializable`, builder/`toBuilder`/`equals`/`hashCode` identity (Swift value types synthesize these), null-argument checks the type system enforces, legacy dual setters, Java test helpers. |
| `DEFERRED` | Depends on a feature the port defers (D4): BigQuery Storage Read API and Arrow (`useReadAPI`, `queryArrow`, `QueryResultsFormat.ARROW`); the beta `Connection` API (`createConnection`, `executeSelect*`, `BigQueryResult*`, `ConnectionSettings`); and OpenTelemetry tracing (deferred unless time permits). `ConnectionProperty` (session/time zone properties on `QueryJobConfiguration`) and `QueryRequestInfo` (the `jobs.query` fast-path builder) are core and are **not** deferred. |

### 1.3 Summary

| Scope | Java tests | Rows | PORT | ADAPT | N/A | DEFERRED |
|---|---|---|---|---|---|---|
| Unit (by behavior row) | 800 in 90 classes | 315 | 198 | 30 | 74 | 13 |
| Unit (by Java test method) | 800 | — | 338 | 112 | 185 | 165 |
| Integration | 214 | 214 | 151 | 12 | 0 | 51 |

### 1.4 Not counted (inactive or inherited)

| Item | Where | Why excluded |
|---|---|---|
| `SerializationTest` | `SerializationTest.java:L32` | Declares no `@Test`; inherits `BaseSerializationTest` serializable/restorable checks. N/A (Java `Serializable`). |
| `testUpdateTableWithSelectedFields` | `it/ITBigQueryTest.java:L2808-L2837` | Missing `@Test`, never runs. Behavior is covered by unit row U.BigQueryImpl.13. |
| `testExecuteSelectWithSession` | `it/ITBigQueryTest.java:L5127-L5137` | Commented out (Connection API `executeUpdate` not implemented). |
| `testRoutineRemoteUDF` | `it/ITRemoteUDFTest.java:L97` | Counted as IT-214 but `@Disabled` in Java (issue java-bigquery#4103). |

### 1.5 Behaviors the Swift unit tests must pin first

These are the highest-risk `PORT` rows. Each needs a deterministic unit
test over a fake HTTP transport:

1. Query routing: `jobs.query` fast path when no `JobID` is given, and the
   `jobs.insert` path when one is given. Also: the fallback to polling
   `getQueryResults` when `jobComplete=false`, and later pages via
   `tabledata.list` (U.BigQueryImpl.46-U.BigQueryImpl.54, `U.QueryRequestInfo.*`).
2. Idempotency: `jobs.query` retries reuse the same `requestId`. `insertAll`
   is retried only when every row has an `insertId`. `jobs.insert` 409
   recovery (U.BigQueryImpl.26, U.BigQueryImpl.27, U.BigQueryImpl.38-U.BigQueryImpl.40, U.BigQueryImpl.62, U.BigQueryImpl.63).
3. Retry classification by HTTP status (500/502/503/504), the rate-limit
   message regex (even on 400/200), transport errors, and the default of 6
   attempts. Java has no reason-based retry: the `backendError` fixture is
   retried because of its 503 code (`bigquery_reference_behavior.md` §2). If
   the Swift design adopts reason-based retry, those tests cite the design
   doc, not Java. Not retried: 400/404/501 (`U.BigQueryException.*`,
   U.BigQueryImpl.15, U.BigQueryImpl.33, U.BigQueryImpl.34, U.BigQueryImpl.58, U.BigQueryImpl.59, U.BigQueryImpl.64).
4. Errors: a 200 `jobs.query` response that carries `errors` throws with all
   errors attached. Reason, location and message are preserved
   (U.BigQueryImpl.65, `U.BigQueryError.*`).
5. 404 contract: Java's `get*` returns null and `delete`/`cancel` return
   false (U.BigQueryImpl.06, IT-011, IT-046, IT-152).
   Exceptions, from `bigquery_reference_behavior.md` §3 "404 handling":
   `delete(JobId)` throws on 404, and `Job.isDone()` is true for a missing
   job. The design must accept or reject these quirks explicitly.
6. Value decoding: `FieldValue` and `FieldValueList` for every type,
   timestamps (float seconds, int64 micros, picosecond ISO strings),
   canonical INTERVAL, RANGE, and case-insensitive name lookup
   (`U.FieldValue.*`, `U.FieldValueList.*`, U.FieldList.01).
7. Query parameter encoding for all scalar, array, struct, and range types,
   including the timestamp text format and BIGNUMERIC formatting
   (`U.QueryParameterValue.*`).
8. REST route table: the HTTP method and path for every RPC
   (U.HttpBigQueryRpc.03).


## 2. Unit test baseline


### 2.1 Client core: BigQueryImpl, RPC, errors, options, upload


#### `BigQueryImplTest` — [BigQueryImplTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/BigQueryImplTest.java) (151 tests; PORT 54 / ADAPT 14 / N/A 1 / DEFERRED 2)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.BigQueryImpl.01 | Options accessor returns configured options | `testGetOptions` L619-L623 | N/A | Java ServiceOptions accessor. | |
| U.BigQueryImpl.02 | datasets.insert: POST with project defaulted from client options | `testCreateDataset` L625-L636 | PORT |  | |
| U.BigQueryImpl.03 | Dataset create/get/update `fields` mask always adds required `datasetReference` (+access, etag) | `testCreateDatasetWithSelectedFields` L638-L655; `testGetDatasetWithSelectedFields` L736-L752; `testUpdateDatasetWithSelectedFields` L927-L948 | PORT |  | |
| U.BigQueryImpl.04 | datasets.insert passes `accessPolicyVersion` query param | `testCreateDatasetWithAccessPolicy` L657-L671 | PORT |  | |
| U.BigQueryImpl.05 | datasets.get by name or DatasetId; missing project filled from client, explicit project kept | `testGetDataset` L673-L682; `testGetDatasetFromDatasetId` L711-L720; `testGetDatasetFromDatasetIdWithProject` L722-L734 | PORT |  | |
| U.BigQueryImpl.06 | 404 on get returns null by default; throws when `throwNotFound` enabled (datasets, tables, models, jobs, routines) | 8 tests in L684-L4172 (`testGetDatasetNotFoundWhenThrowIsDisabled, testGetDatasetNotFoundWhenThrowIsEnabled, testGetTableNotFoundWhenThrowIsDisabled, testGetTableNotFoundWhenThrowIsEnabled, testGetModelNotFoundWhenThrowIsEnabled, testGetJobNotFoundWhenThrowIsDisabled, testGetJobNotFoundWhenThrowIsEnabled, testGetRoutineWithEnabledThrowNotFoundException`) | ADAPT | Swift: pick one documented 404 contract (e.g. `get` returns nil / throws `.notFound`) and test both paths. | |
| U.BigQueryImpl.07 | datasets.list paging (default/explicit project, empty, all/labelFilter/pageSize/pageToken options) | `testListDatasets` L754-L770; `testListDatasetsWithProjects` L772-L788; `testListEmptyDatasets` L790-L803; `testListDatasetsWithOptions` L805-L822 | ADAPT | Java Page -> Swift AsyncSequence + per-page API; test token propagation and options. | |
| U.BigQueryImpl.08 | projects.list maps id/numericId/projectReference/friendlyName; empty list | `testListProjects` L824-L852; `testListEmptyProjects` L854-L866 | PORT |  | |
| U.BigQueryImpl.09 | datasets.delete returns true; DatasetId/project variants | `testDeleteDataset` L868-L876; `testDeleteDatasetFromDatasetId` L878-L886; `testDeleteDatasetFromDatasetIdWithProject` L888-L898 | PORT | 404 -> false covered by IT-046. | |
| U.BigQueryImpl.10 | datasets.delete `deleteContents=true` option | `testDeleteDatasetWithOptions` L900-L909 | PORT |  | |
| U.BigQueryImpl.11 | datasets.patch sends updated resource with client project filled | `testUpdateDataset` L911-L925 | PORT |  | |
| U.BigQueryImpl.12 | tables.insert (standard, external, empty project replaced by client project) | `testCreateTable` L950-L961; `tesCreateExternalTable` L963-L980; `testCreateTableWithoutProject` L982-L994 | PORT |  | |
| U.BigQueryImpl.13 | Table create/get/update `fields` mask always adds required `tableReference` (+schema, etag) | `testCreateTableWithSelectedFields` L996-L1012; `testGetTableWithSelectedFields` L1223-L1239; `testUpdateTableWithSelectedFields` L1529-L1549 | PORT |  | |
| U.BigQueryImpl.14 | tables.get by (dataset, table) / TableId with/without project | `testGetTable` L1014-L1024; `testGetTableFromTableId` L1180-L1190; `testGetTableFromTableIdWithProject` L1192-L1206; `testGetTableFromTableIdWithoutProject` L1208-L1221 | PORT |  | |
| U.BigQueryImpl.15 | 503 `backendError` on tables.get is retried, then succeeds (2 calls) | `testGetTableFailureShouldRetryServerErrors` L1026-L1051 | PORT |  | |
| U.BigQueryImpl.16 | Custom retry algorithm that refuses retry -> single attempt, error surfaced | `testGetTableFailureWithCustomRetryAlgorithmShouldNotRetry` L1053-L1097 | ADAPT | Swift: injectable retry policy (gax RetryPolicy) instead of ResultRetryAlgorithm. | |
| U.BigQueryImpl.17 | tables.list paging + options (DatasetId/project variants, pageSize/pageToken) | `testListTables` L1241-L1257; `testListTablesFromDatasetId` L1310-L1325; `testListTablesFromDatasetIdWithProject` L1327-L1343; `testListTablesWithOptions` L1362-L1378 | ADAPT | AsyncSequence. | |
| U.BigQueryImpl.18 | tables.list item mapping keeps timePartitioning (incl. null type), rangePartitioning, labels | `testListTablesReturnedParameters` L1259-L1274; `testListTablesReturnedParametersNullType` L1276-L1291; `testListTablesWithRangePartitioning` L1293-L1308; `testListTablesWithLabels` L1345-L1360 | PORT |  | |
| U.BigQueryImpl.19 | listPartitions reads `$__PARTITIONS_SUMMARY__` meta-table and returns partition ids | `testListPartition` L1132-L1148 | PORT |  | |
| U.BigQueryImpl.20 | tables.delete returns true (TableId/project variants) | `testDeleteTable` L1414-L1421; `testDeleteTableFromTableId` L1423-L1430; `testDeleteTableFromTableIdWithProject` L1432-L1442; `testDeleteTableFromTableIdWithoutProject` L1444-L1453 | PORT |  | |
| U.BigQueryImpl.21 | tables.patch (project defaulting) | `testUpdateTable` L1481-L1494; `testUpdateTableWithoutProject` L1515-L1527 | PORT |  | |
| U.BigQueryImpl.22 | Updating external table sends schema at table level and nulls externalDataConfiguration.schema | `testUpdateExternalTableWithNewSchema` L1496-L1513 | PORT | Wire quirk. | |
| U.BigQueryImpl.23 | tables.patch `autodetect_schema=true` option | `testUpdateTableWithAutoDetectSchema` L1551-L1569 | PORT |  | |
| U.BigQueryImpl.24 | models.get / patch / delete | `testGetModel` L1103-L1113; `testUpdateModel` L1464-L1479; `testDeleteModel` L1455-L1462 | PORT |  | |
| U.BigQueryImpl.25 | models.list paging (dataset name / DatasetId) | `testListModels` L1380-L1395; `testListModelsWithModelId` L1397-L1412 | ADAPT | AsyncSequence. | |
| U.BigQueryImpl.26 | insertAll WITH insertIds retried on 500 (idempotent); per-row errors mapped by index | `testInsertAllWithRowIdShouldRetry` L1571-L1622 | PORT | Key idempotency rule. | |
| U.BigQueryImpl.27 | insertAll WITHOUT insertIds is NOT retried | `testInsertAllWithoutRowIdShouldNotRetry` L1624-L1666 | PORT | Key idempotency rule. Swift auto-generates insertIds (#8), so this applies to the opt-out path. | |
| U.BigQueryImpl.28 | insertAll body (insertId, json, skipInvalidRows, ignoreUnknownValues, templateSuffix) routed to table's project | `testInsertAllWithProject` L1668-L1718; `testInsertAllWithProjectInTable` L1720-L1771 | PORT |  | |
| U.BigQueryImpl.29 | tabledata.list (dataset/table, TableId, other project) | `testListTableData` L1773-L1784; `testListTableDataFromTableId` L1786-L1797; `testListTableDataFromTableIdWithProject` L1799-L1812 | PORT |  | |
| U.BigQueryImpl.30 | tabledata.list options maxResults/pageToken/startIndex | `testListTableDataWithOptions` L1814-L1831 | PORT |  | |
| U.BigQueryImpl.31 | tabledata.list next page reuses pageToken and resets startIndex to 0 | `testListTableDataWithNextPage` L1833-L1869 | ADAPT | Row AsyncSequence must follow the same token/startIndex rule. | |
| U.BigQueryImpl.32 | jobs.insert sends caller JobId in jobReference | `testCreateJobSuccess` L1879-L1894 | PORT |  | |
| U.BigQueryImpl.33 | jobs.insert retries transport errors (UnknownHost, Connect) | `testCreateJobFailureShouldRetryExceptionHandlerExceptions` L1896-L1914 | PORT | Swift: URLError equivalents. | |
| U.BigQueryImpl.34 | jobs.insert retries 500/502/503 and rate-limit message even on 400/200 | `testCreateJobFailureShouldRetry` L1916-L1939 | PORT |  | |
| U.BigQueryImpl.35 | Per-call BigQueryRetryConfig (retry on message / regex) honoured or not | `testCreateJobWithBigQueryRetryConfigFailureShouldRetry` L1941-L1972; `testCreateJobWithBigQueryRetryConfigFailureShouldNotRetry` L1974-L2011 | ADAPT | Swift: per-call retry policy option. | |
| U.BigQueryImpl.36 | Per-call RetryOptions maxAttempts honoured (4 vs 1) | `testCreateJobWithRetryOptionsFailureShouldRetry` L2013-L2036; `testCreateJobWithRetryOptionsFailureShouldNotRetry` L2038-L2070 | ADAPT | Swift: per-call retry policy option. | |
| U.BigQueryImpl.37 | jobs.insert `fields` mask always adds jobReference,configuration; job routed to its own project | `testCreateJobWithSelectedFields` L2072-L2091; `testCreateJobWithProjectId` L2174-L2195 | PORT |  | |
| U.BigQueryImpl.38 | 409 on jobs.insert with caller JobId surfaces error (no lookup) | `testCreateJobNoGet` L2093-L2111 | PORT |  | |
| U.BigQueryImpl.39 | 409 on jobs.insert with generated JobId -> jobs.get returns existing job | `testCreateJobTryGet` L2113-L2140 | PORT |  | |
| U.BigQueryImpl.40 | 409 'Already Exists: Job' with caller JobId -> jobs.get(fields=statistics) recovers | `testCreateJobTryGetNotRandom` L2142-L2172 | PORT |  | |
| U.BigQueryImpl.41 | jobs.delete with location | `testDeleteJob` L2197-L2205 | PORT |  | |
| U.BigQueryImpl.42 | jobs.get with location from JobId or client default; project variants | `testGetJob` L2207-L2215; `testGetJobWithLocation` L2217-L2227; `testGetJobFromJobId` L2254-L2262; `testGetJobFromJobIdWithLocation` L2264-L2274; `testGetJobFromJobIdWithProject` L2276-L2288; `testGetJobFromJobIdWithProjectWithLocation` L2290-L2303 | PORT |  | |
| U.BigQueryImpl.43 | jobs.list paging + options | `testListJobs` L2305-L2329; `testListJobsWithOptions` L2331-L2357 | ADAPT | AsyncSequence. | |
| U.BigQueryImpl.44 | jobs.list `fields` mask wraps as `nextPageToken,jobs(...)` incl. jobReference,configuration,statistics,state,errorResult | `testListJobsWithSelectedFields` L2359-L2393 | PORT |  | |
| U.BigQueryImpl.45 | jobs.cancel (JobId/project variants) | `testCancelJob` L2395-L2401; `testCancelJobFromJobId` L2403-L2409; `testCancelJobFromJobIdWithProject` L2411-L2418 | PORT |  | |
| U.BigQueryImpl.46 | query() with explicit JobId: jobs.insert -> getQueryResults wait -> tabledata.list on destination table | `testQueryRequestCompleted` L2420-L2473 | PORT |  | |
| U.BigQueryImpl.47 | query() without JobId uses jobs.query fast path; request carries query/defaultDataset/useQueryCache, no location | `testFastQueryRequestCompleted` L2475-L2513 | PORT |  | |
| U.BigQueryImpl.48 | Fast path forwards jobTimeoutMs | `testFastQueryRequestCompletedWithTimeout` L2515-L2556 | PORT |  | |
| U.BigQueryImpl.49 | JOB_CREATION_REQUIRED still uses jobs.query, returns jobId, never jobs.insert | `testQueryRequestRequiredJobCreationCompleted` L2558-L2606 | PORT |  | |
| U.BigQueryImpl.50 | Client default location sent on jobs.query; result exposes totalBytesProcessed/cacheHit | `testFastQueryRequestCompletedWithLocation` L2608-L2649 | PORT |  | |
| U.BigQueryImpl.51 | Fast path with pageToken: later pages via jobs.get + tabledata.list | `testFastQueryMultiplePages` L2651-L2705 | PORT |  | |
| U.BigQueryImpl.52 | Fast path jobComplete=false falls back to polling getQueryResults then reading results | `testFastQuerySlowDdl` L2707-L2771 | PORT |  | |
| U.BigQueryImpl.53 | Job.getQueryResults pageSize forwarded to tabledata.list | `testQueryRequestCompletedOptions` L2773-L2829 | PORT |  | |
| U.BigQueryImpl.54 | getQueryResults polled until jobComplete=true | `testQueryRequestCompletedOnSecondAttempt` L2831-L2894 | PORT |  | |
| U.BigQueryImpl.55 | queryWithTimeout returns TableResult (stats: statementType, bytes billed/processed, slotMs, DML rows, sessionInfo) and sends timeoutMs | `testQueryWithTimeoutSetsTimeout` L2896-L2930 | ADAPT | Java returns Object (TableResult\|Job); Swift: enum result. | |
| U.BigQueryImpl.56 | Arrow results format / queryArrow fast+slow path, paging, page fetcher, missing schema, incomplete job | 12 tests in L2932-L3703 (`testQueryArrowDefaultsToJobCreationOptional, testQueryArrowDefaultsToUSLocationWhenUnspecified, testQueryWithArrowFormatSlowPathFallback, testQueryWithArrowFormatFastPath, testQueryWithArrowFormatMultiplePages, testQueryWithArrowFormatMultiplePagesWithMaxResults, testArrowQueryPageFetcherSerialization, testQueryWithArrowFormatMissingSerializedSchema, testQueryWithArrowFormatIncompleteJob, testQueryWithArrowFormatIncompleteJobMissingJobReference, testQueryWithArrowFormatIncompleteJobJobNotFound, testQueryWithArrowFormatOpaquePageToken`) | DEFERRED | Arrow / Storage Read API deferred. | |
| U.BigQueryImpl.57 | jobs.getQueryResults (default/other project; timeoutMs/startIndex/maxResults/pageToken options) | `testGetQueryResults` L3705-L3727; `testGetQueryResultsWithProject` L3773-L3795; `testGetQueryResultsWithOptions` L3797-L3824 | PORT |  | |
| U.BigQueryImpl.58 | getQueryResults retried on 500/502/503/504 + rateLimitExceeded | `testGetQueryResultsRetry` L3729-L3771 | PORT |  | |
| U.BigQueryImpl.59 | 500 on datasets.get retried; 501 not retried and message preserved | `testGetDatasetRetryableException` L3826-L3841; `testNonRetryableException` L3843-L3858 | PORT |  | |
| U.BigQueryImpl.60 | Unexpected runtime error wrapped into BigQueryException keeping message | `testRuntimeException` L3860-L3874 | ADAPT | Swift: unknown errors wrapped/propagated in the single error type. | |
| U.BigQueryImpl.61 | query() with dryRun=true is rejected (UnsupportedOperationException) | `testQueryDryRun` L3876-L3889 | ADAPT | Swift may instead return dry-run statistics; document choice. | |
| U.BigQueryImpl.62 | jobs.query retried on 5xx reusing the SAME requestId (SELECT/DML/DDL) | `testFastQuerySQLShouldRetry` L3891-L3930; `testFastQueryDMLShouldRetry` L3932-L3971; `testFastQueryDDLShouldRetry` L4046-L4084 | PORT | Idempotency. | |
| U.BigQueryImpl.63 | jobs.query retried on rate-limit message, same requestId | `testFastQueryRateLimitIdempotency` L3973-L4019 | PORT |  | |
| U.BigQueryImpl.64 | Rate-limit regex matches 'exceeded rate limits' but not quota-for-table-update messages | `testRateLimitRegEx` L4021-L4044 | PORT |  | |
| U.BigQueryImpl.65 | jobs.query 200 response with `errors` -> exception carrying all BigQueryErrors | `testFastQueryBigQueryException` L4086-L4121 | PORT |  | |
| U.BigQueryImpl.66 | routines.insert/get/update(PUT)/delete | `testCreateRoutine` L4123-L4134; `testGetRoutine` L4136-L4146; `testGetRoutineWithRountineId` L4148-L4158; `testUpdateRoutine` L4174-L4190; `testDeleteRoutine` L4224-L4231 | PORT |  | |
| U.BigQueryImpl.67 | routines.list paging (dataset name / DatasetId) | `testListRoutines` L4192-L4206; `testListRoutinesWithDatasetId` L4208-L4222 | ADAPT | AsyncSequence. | |
| U.BigQueryImpl.68 | writer(): opens resumable load upload with job config; close returns Job | `testWriteWithJob` L4233-L4257; `testWriteChannel` L4259-L4283 | ADAPT | Swift: async upload API instead of WriteChannel. | |
| U.BigQueryImpl.69 | tables getIamPolicy / setIamPolicy / testIamPermissions on `projects/p/datasets/d/tables/t` | `testGetIamPolicy` L4285-L4297; `testSetIamPolicy` L4299-L4313; `testTestIamPermissions` L4315-L4333 | PORT |  | |
| U.BigQueryImpl.70 | testIamPermissions with null permissions -> empty list | `testTestIamPermissionsWhenNoPermissionsGranted` L4335-L4353 | PORT |  | |
| U.BigQueryImpl.71 | close() lifecycle of BigQueryReadClient(s) (idempotent, try-with-resources, regional clients) | `testCloseClosesBigQueryReadClient` L4355-L4365; `testCloseIsIdempotent` L4367-L4378; `testCloseWithoutReadClientDoesNotThrow` L4380-L4384; `testTryWithResources` L4386-L4395; `testGetBigQueryReadClientAfterCloseThrows` L4397-L4403; `testCloseClosesAllRegionalBigQueryReadClients` L4405-L4419 | DEFERRED | Storage Read API client deferred. | |

#### `HttpBigQueryRpcTest` — [spi/v2/HttpBigQueryRpcTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/spi/v2/HttpBigQueryRpcTest.java) (81 tests; PORT 3 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.HttpBigQueryRpc.01 | datasets.list item -> Dataset mapping keeps kind/id/friendlyName/reference/labels/location | `testListToDataset` L194-L215 | PORT |  | |
| U.HttpBigQueryRpc.02 | projects.list request | `testListProjects` L283-L305 | PORT |  | |
| U.HttpBigQueryRpc.03 | REST route table: HTTP method + path for every RPC (datasets/tables/models/routines CRUD, PUT routines, insertAll, tabledata, jobs get/list/insert/cancel/delete, queries get/post, IAM `:getIamPolicy/:setIamPolicy/:testIamPermissions`) | 35 tests in L1233-L1770 | PORT | Swift: one parameterized @Test over a route table with a capture transport. | |
| U.HttpBigQueryRpc.04 | OpenTelemetry spans/attributes per RPC (incl. url.domain default/override, error attributes, uri template) | 44 tests in L227-L1785 | DEFERRED | OpenTelemetry: DEFERRED per D4 (#4); Swift would use swift-distributed-tracing. | |

#### `TableDataWriteChannelTest` — [TableDataWriteChannelTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TableDataWriteChannelTest.java) (13 tests; PORT 4 / ADAPT 2 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.TableDataWriteChannel.01 | Opening the resumable load session (jobs.insert upload) returns upload id | `testCreate` L103-L118 | PORT |  | |
| U.TableDataWriteChannel.02 | Open retried on retryable error; non-retryable surfaces | `testCreateRetryableErrors` L120-L138; `testCreateNonRetryableError` L140-L160 | PORT |  | |
| U.TableDataWriteChannel.03 | Buffers writes until a full chunk then uploads (min chunk 256 KiB, default 60x = 15 MiB, custom chunk size) | `testWriteWithoutFlush` L162-L177; `testWriteWithFlush` L179-L213 | ADAPT | Swift async upload API; keep chunk granularity. | |
| U.TableDataWriteChannel.04 | Chunk upload retried on retryable error; non-retryable surfaces | `testWritesAndFlushRetryableErrors` L215-L259; `testWritesAndFlushNonRetryableError` L261-L301 | PORT |  | |
| U.TableDataWriteChannel.05 | close() uploads final chunk (last=true) and yields the load Job | `testCloseWithoutFlush` L303-L327; `testCloseWithFlush` L329-L356 | PORT |  | |
| U.TableDataWriteChannel.06 | Write after close fails | `testWriteClosed` L358-L380 | ADAPT | API shape may make this unrepresentable. | |
| U.TableDataWriteChannel.07 | RestorableState capture/restore/equality | `testSaveAndRestore` L382-L422; `testSaveAndRestoreClosed` L424-L456; `testStateEquals` L458-L480 | N/A | Java RestorableState mechanism. | |

#### `BigQueryErrorTest` — [BigQueryErrorTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/BigQueryErrorTest.java) (2 tests; PORT 2 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.BigQueryError.01 | BigQueryError carries reason/location/message/debugInfo | `testConstructor` L34-L44 | PORT |  | |
| U.BigQueryError.02 | ErrorProto JSON round trip | `testToAndFromPb` L46-L50 | PORT |  | |

#### `BigQueryExceptionTest` — [BigQueryExceptionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/BigQueryExceptionTest.java) (4 tests; PORT 2 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.BigQueryException.01 | Retryable classification: 500/502/503/504 and IO (socket timeout) retryable, 400/404 not; reason taken from BigQueryError | `testBigQueryException` L50-L137 | PORT |  | |
| U.BigQueryException.02 | RetryHelperException unwrapping | `testTranslateAndThrow` L139-L168 | N/A | Java RetryHelper mechanics. | |
| U.BigQueryException.03 | Default handler retries SocketException up to 6 attempts total | `testDefaultExceptionHandler` L170-L198 | PORT | Pins default max attempts. | |
| U.BigQueryException.04 | Custom exception handler retryOn/abortOn | `testCustomExceptionHandler` L200-L251 | ADAPT | Swift: custom retry policy. | |

#### `BigQueryOptionsTest` — [BigQueryOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/BigQueryOptionsTest.java) (7 tests; PORT 1 / ADAPT 1 / N/A 2 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.BigQueryOptions.01 | Only HTTP transport accepted | `testInvalidTransport` L34-L43 | N/A | Java transport option. | |
| U.BigQueryOptions.02 | Default DataFormatOptions: useInt64Timestamp=false, timestamp output format unspecified | `dataFormatOptions_createdByDefault` L45-L54 | PORT |  | |
| U.BigQueryOptions.03 | Legacy setUseInt64Timestamps vs DataFormatOptions precedence | `nonBuilderSetUseInt64Timestamp_capturedInDataFormatOptions` L56-L66; `nonBuilderSetUseInt64Timestamp_overridesEverything` L68-L74; `noDataFormatOptions_capturesUseInt64TimestampSetInBuilder` L76-L82; `dataFormatOptionsSetterHasPrecedence` L84-L94 | ADAPT | Java dual legacy setter collapses to one Swift value, but the wire outcome matters (survey #7): assert jobs.query/tabledata.list always request int64 timestamps (`formatOptions.useInt64Timestamp=true`). | |
| U.BigQueryOptions.04 | useJwtAccessWithScope defaults false | `testUseJwtAccessWithScope_defaultsToFalse` L96-L101 | N/A | Java auth library detail. | |

#### `OptionTest` — [OptionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/OptionTest.java) (3 tests; PORT 0 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Option.01 | Option equals/hashCode/constructor | `testEquals` L38-L43; `testHashCode` L45-L48; `testConstructor` L50-L58 | N/A | Java Option plumbing. | |

#### `PolicyHelperTest` — [PolicyHelperTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/PolicyHelperTest.java) (2 tests; PORT 1 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.PolicyHelper.01 | IAM Policy <-> REST Policy conversion with and without bindings | `testConversionWithBindings` L60-L68; `testConversionNoBindings` L70-L80 | PORT |  | |

#### `AnnotationsTest` — [AnnotationsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/AnnotationsTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Annotations.01 | Labels map: null/empty handling and JSON-null values (label deletion) survive round trip | `testFromUser` L29-L43; `testFromToPb` L45-L60 | PORT | Swift: patch must be able to send `"label": null`. | |
| U.Annotations.02 | Null label key rejected | `testNullKey` L62-L71 | N/A | Type system forbids nil keys. | |

#### `RemoteBigQueryHelperTest` — [testing/RemoteBigQueryHelperTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/testing/RemoteBigQueryHelperTest.java) (2 tests; PORT 0 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.RemoteBigQueryHelper.01 | forceDelete deletes dataset with contents | `testForceDelete` L68-L75 | ADAPT | Becomes a Swift IT helper (cleanup), not public API. | |
| U.RemoteBigQueryHelper.02 | Helper from credentials stream | `testCreateFromStream` L77-L88 | N/A | Java test helper. | |

#### `BigQueryTelemetryTracerTest` — [telemetry/BigQueryTelemetryTracerTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/telemetry/BigQueryTelemetryTracerTest.java) (10 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.BigQueryTelemetryTracer.01 | Span error/exception/common attributes | 10 tests in L58-L185 (`testAddServerErrorResponseToSpan_DetailsNull, testAddServerErrorResponseToSpan_UsesStatusMessage, testAddServerErrorResponseToSpan_ErrorsNull, testAddServerErrorResponseToSpan_ErrorsEmpty, testAddServerErrorResponseToSpan_WithErrors_MessageAndReasonNotNull, testAddServerErrorResponseToSpan_WithErrors_MessageNull, testAddServerErrorResponseToSpan_WithErrors_ReasonNull, testAddExceptionToSpan_WithMessage, testAddExceptionToSpan_NoMessage, testAddCommonAttributeToSpan`) | DEFERRED | OpenTelemetry: DEFERRED per D4 (#4). | |

#### `HttpTracingRequestInitializerTest` — [telemetry/HttpTracingRequestInitializerTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/telemetry/HttpTracingRequestInitializerTest.java) (15 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.HttpTracingRequestInitializer.01 | HTTP tracing spans, header propagation, redaction, body sizes, retry count | 15 tests in L92-L381 (`testAllAttributesAreSetOnSuccessfulCall, testExistingParentAttributesAreNotAffectedByRequestAttributes, testNoSpanIsCreatedIfNoActiveSpan, testTraceContextIsPropagatedInHeaders, testDelegateInitializerIsCalled, testUnsuccessfulResponseHandlerSetsAttributesAndCallsOriginal, testUnsuccessfulResponseHandlerSetsErrorIfNoOriginal, testUrlQueryParametersAreRedacted, testUrlCredentialsAreRedacted, testAddRequestBodySizeToSpan_ExceptionHandled, testAddRequestBodySizeToSpan_NullBody, testAddRequestBodySizeToSpan_WithEncoding, testRetryCountFromContext, testAddRequestBodySizeToSpan, testAddResponseBodySizeToSpan_NullLength`) | DEFERRED | OpenTelemetry: DEFERRED per D4 (#4). | |

### 2.2 Query fast path, Connection API and Arrow


#### `QueryRequestInfoTest` — [QueryRequestInfoTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/QueryRequestInfoTest.java) (4 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.QueryRequestInfo.01 | Fast-path eligibility (isFastQuerySupported) incl. timeout and JOB_CREATION_REQUIRED configs | `testIsFastQuerySupported` L176-L182 | PORT | Core of query() routing. | |
| U.QueryRequestInfo.02 | QueryRequest body built from config (jobTimeoutMs etc.) | `testToPb` L184-L190 | PORT |  | |
| U.QueryRequestInfo.03 | formatOptions.useInt64Timestamp follows DataFormatOptions | `testInt64Timestamp` L211-L224 | PORT |  | |
| U.QueryRequestInfo.04 | Equality of request infos | `equalTo` L192-L209 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ConnectionPropertyTest` — [ConnectionPropertyTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ConnectionPropertyTest.java) (4 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ConnectionProperty.01 | ConnectionProperty (key/value) JSON round trip | `testToAndFromPb` L51-L55 | PORT | Used by QueryJobConfiguration.connectionProperties (sessions, time_zone). | |
| U.ConnectionProperty.02 | Builder mechanics | `testToBuilder` L30-L37; `testToBuilderIncomplete` L39-L43; `testBuilder` L45-L49 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ArrowDeserializerTest` — [ArrowDeserializerTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ArrowDeserializerTest.java) (20 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ArrowDeserializer.01 | Arrow schema/record batch -> BigQuery schema/FieldValues (primitives, struct, repeated, nulls, timestamps, paging/maxResults buffering, errors) | 20 tests in L69-L901 | DEFERRED | Arrow deferred. | |

#### `ArrowPojoUtilsTest` — [ArrowPojoUtilsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ArrowPojoUtilsTest.java) (11 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ArrowPojoUtils.01 | Arrow schema -> BigQuery schema type mapping and unsupported types | 11 tests in L36-L263 (`testArrowSchemaToBigQuerySchema_Primitives, testArrowSchemaToBigQuerySchema_BigNumeric, testArrowSchemaToBigQuerySchema_NestedStruct, testArrowSchemaToBigQuerySchema_ListPrimitives, testArrowSchemaToBigQuerySchema_ListOfStruct, testArrowSchemaToBigQuerySchema_EmptyListThrowsException, testArrowSchemaToBigQuerySchema_LargeTypesThrowException, testArrowSchemaToBigQuerySchema_NestedListThrowsException, testArrowSchemaToBigQuerySchema_FixedSizeListThrowsException, testArrowSchemaToBigQuerySchema_UnsupportedTypeThrowsException, testArrowSchemaToBigQuerySchema_EmptyStructThrowsException`) | DEFERRED | Arrow deferred. | |

#### `ArrowQueryPageFetcherTest` — [ArrowQueryPageFetcherTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ArrowQueryPageFetcherTest.java) (5 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ArrowQueryPageFetcher.01 | Arrow page fetching (single/multi page, maxResults, US default location, serialization) | `testGetNextPage_singlePage` L123-L171; `testGetNextPage_multiplePagesWithPageSizeOption` L173-L239; `testGetNextPage_respectsMaxResults` L241-L289; `testGetNextPage_missingLocationDefaultsToUS` L291-L336; `testSerialization` L338-L375 | DEFERRED | Arrow deferred. | |

#### `ArrowQueryResultTest` — [ArrowQueryResultTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ArrowQueryResultTest.java) (9 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ArrowQueryResult.01 | ArrowQueryResult iteration, close, multi-batch, read-session fallback | 9 tests in L130-L417 (`testSingleBatchIteration, testIteratorCannotBeCreatedTwice, testCloseIsIdempotentAndReleasesResources, testMultiBatchStreaming, testQueryIdAndJobCreationReason, testStatelessSingleBatchIterationWithoutJobId, testFromReadSessionFallback, testNullOrEmptySchemaProducesEmptyIterator, testFromReadSessionWithMultipleStreamsThrowsIllegalArgumentException`) | DEFERRED | Arrow deferred. | |

#### `BigQueryResultImplTest` — [BigQueryResultImplTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/BigQueryResultImplTest.java) (3 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.BigQueryResultImpl.01 | Connection API ResultSet over FieldValueList and Read API | `testResultSetFieldValueList` L99-L199; `testResultSetReadApi` L201-L295; `testResultSetReadApiGetLongByColumnIndexPreservesInt64Value` L297-L318 | DEFERRED | Connection API deferred. | |

#### `ConnectionImplTest` — [ConnectionImplTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ConnectionImplTest.java) (22 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ConnectionImpl.01 | Connection API executeSelect fast/slow/legacy paths, async, dry run, buffering, Read API switch | 22 tests in L178-L796 | DEFERRED | Connection API deferred. | |

#### `ConnectionSettingsTest` — [ConnectionSettingsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ConnectionSettingsTest.java) (3 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ConnectionSettings.01 | ConnectionSettings builder | `testToBuilder` L118-L121; `testToBuilderIncomplete` L123-L128; `testBuilder` L130-L135 | DEFERRED | Connection API deferred. | |

### 2.3 Jobs and results


#### `JobTest` — [JobTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/JobTest.java) (27 tests; PORT 6 / ADAPT 4 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Job.01 | Builder / toBuilder / bigquery accessor | `testBuilder` L108-L130; `testToBuilder` L132-L135; `testBigQuery` L597-L600 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |
| U.Job.02 | exists() true/false via jobs.get | `testExists_True` L137-L143; `testExists_False` L145-L151 | ADAPT | Java 'live object' convenience method delegating to BigQuery; Swift exposes the operation on the client (or a thin wrapper) - test the client call. | |
| U.Job.03 | isDone(): DONE -> true, RUNNING -> false, job vanished -> true (fields=status) | `testIsDone_True` L153-L158; `testIsDone_False` L160-L167; `testIsDone_NotExists` L169-L177 | PORT |  | |
| U.Job.04 | waitFor polls jobs.get until DONE (with checking period) | `testWaitFor` L179-L194; `testWaitForWithCheckingPeriod` L353-L373 | PORT |  | |
| U.Job.05 | waitFor on query job polls getQueryResults then jobs.get; empty results (with/without schema) handled | `testWaitForAndGetQueryResultsEmpty` L196-L238; `testWaitForAndGetQueryResultsEmptyWithSchema` L240-L283; `testWaitForAndGetQueryResults` L285-L335 | PORT |  | |
| U.Job.06 | getQueryResults on non-query job is unsupported | `testWaitForAndGetQueryResults_Unsupported` L337-L342 | PORT |  | |
| U.Job.07 | waitFor returns null when job disappears | `testWaitFor_Null` L344-L351; `testWaitForWithCheckingPeriod_Null` L375-L386 | ADAPT | Swift: nil or notFound error. | |
| U.Job.08 | waitFor total timeout -> error | `testWaitForWithTimeout` L388-L405 | PORT | Swift: Duration timeout + Task cancellation. | |
| U.Job.09 | waitFor with BigQueryRetryConfig retries rate-limit errors from getQueryResults, not others | `testWaitForWithBigQueryRetryConfig` L407-L447; `testWaitForWithBigQueryRetryConfigShouldRetry` L449-L498; `testWaitForWithBigQueryRetryConfigErrorShouldNotRetry` L500-L547 | ADAPT | Swift per-call retry policy. | |
| U.Job.10 | reload / cancel delegate to client; reload propagates errors and null | `testReload` L549-L557; `testReloadJobException` L559-L571; `testReloadNull` L573-L578; `testReloadWithOptions` L580-L588; `testCancel` L590-L595 | ADAPT | Java 'live object' convenience method delegating to BigQuery; Swift exposes the operation on the client (or a thin wrapper) - test the client call. | |
| U.Job.11 | Job JSON round trip incl. job without configuration | `testToAndFromPb` L602-L605; `testToAndFromPbWithoutConfiguration` L607-L611 | PORT |  | |

#### `JobInfoTest` — [JobInfoTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/JobInfoTest.java) (6 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.JobInfo.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L299-L334 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.JobInfo.02 | setProjectId propagates project to JobId and configuration table references | `testSetProjectId` L336-L358 | PORT |  | |
| U.JobInfo.03 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L206-L228; `testOf` L230-L252; `testToBuilderIncomplete` L254-L258; `testBuilder` L260-L297 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `JobIdTest` — [JobIdTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/JobIdTest.java) (4 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.JobId.01 | JobId of(project, job, location) | `testOf` L28-L34 | PORT |  | |
| U.JobId.02 | JobReference JSON round trip | `testToPbAndFromPb` L42-L46 | PORT |  | |
| U.JobId.03 | setProjectId fills missing project | `testSetProjectId` L48-L51 | PORT |  | |
| U.JobId.04 | equals/hashCode | `testEquals` L36-L40 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `JobStatusTest` — [JobStatusTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/JobStatusTest.java) (2 tests; PORT 2 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.JobStatus.01 | JobStatus state + errorResult + executionErrors | `testConstructor` L38-L51 | PORT |  | |
| U.JobStatus.02 | JobStatus JSON round trip | `testToPbAndFromPb` L53-L58 | PORT |  | |

#### `JobStatisticsTest` — [JobStatisticsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/JobStatisticsTest.java) (3 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.JobStatistics.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L360-L386 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.JobStatistics.02 | Partial/incomplete statistics parse without failure | `testIncomplete` L388-L422 | PORT |  | |
| U.JobStatistics.03 | Builder / toBuilder / equals / factory mechanics | `testBuilder` L274-L358 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `CopyJobConfigurationTest` — [CopyJobConfigurationTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/CopyJobConfigurationTest.java) (8 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.CopyJobConfiguration.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L112-L133 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.CopyJobConfiguration.02 | setProjectId fills project on table refs but never overrides an explicit one | `testSetProjectId` L135-L143; `testSetProjectIdDoNotOverride` L145-L165 | PORT |  | |
| U.CopyJobConfiguration.03 | Configuration type discriminator | `testGetType` L167-L171 | PORT | Swift: enum case. | |
| U.CopyJobConfiguration.04 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L66-L79; `testOf` L81-L89; `testToBuilderIncomplete` L91-L96; `testBuilder` L98-L110 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ExtractJobConfigurationTest` — [ExtractJobConfigurationTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ExtractJobConfigurationTest.java) (8 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ExtractJobConfiguration.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L196-L216 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ExtractJobConfiguration.02 | setProjectId fills project on table refs but never overrides an explicit one | `testSetProjectId` L218-L225; `testSetProjectIdDoNotOverride` L227-L241 | PORT |  | |
| U.ExtractJobConfiguration.03 | Configuration type discriminator | `testGetType` L243-L249 | PORT | Swift: enum case. | |
| U.ExtractJobConfiguration.04 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L90-L115; `testOf` L117-L147; `testToBuilderIncomplete` L149-L155; `testBuilder` L157-L194 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `LoadJobConfigurationTest` — [LoadJobConfigurationTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/LoadJobConfigurationTest.java) (7 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.LoadJobConfiguration.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L228-L234 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.LoadJobConfiguration.02 | setProjectId fills project on table refs but never overrides an explicit one | `testSetProjectId` L236-L240; `testSetProjectIdDoNotOverride` L242-L250 | PORT |  | |
| U.LoadJobConfiguration.03 | Configuration type discriminator | `testGetType` L252-L255 | PORT | Swift: enum case. | |
| U.LoadJobConfiguration.04 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L170-L200; `testOf` L202-L220; `testToBuilderIncomplete` L222-L226 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `QueryJobConfigurationTest` — [QueryJobConfigurationTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/QueryJobConfigurationTest.java) (15 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 1)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.QueryJobConfiguration.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L182-L199 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.QueryJobConfiguration.02 | setProjectId fills project on table refs but never overrides an explicit one | `testSetProjectId` L201-L206; `testSetProjectIdDoNotOverride` L208-L217 | PORT |  | |
| U.QueryJobConfiguration.03 | Configuration type discriminator | `testGetType` L219-L222 | PORT | Swift: enum case. | |
| U.QueryJobConfiguration.04 | Arrow results format / serialization options defaults and null checks | `testArrowConfigurations` L245-L272; `testArrowSerializationOptionsNullChecks` L274-L291; `testQueryJobConfigurationDefaults` L293-L305; `testArrowFormatWithNullSerializationOptions` L307-L321; `testQueryJobConfigurationArrowNullChecks` L323-L334 | DEFERRED | Arrow deferred (default STRUCT_ENCODING noted). | |
| U.QueryJobConfiguration.05 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L159-L168; `testOf` L170-L174; `testToBuilderIncomplete` L176-L180; `testPositionalParameter` L224-L229; `testNamedParameter` L231-L236; `testJobCreationMode` L238-L243 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `WriteChannelConfigurationTest` — [WriteChannelConfigurationTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/WriteChannelConfigurationTest.java) (6 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.WriteChannelConfiguration.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L204-L211 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.WriteChannelConfiguration.02 | setProjectId never overrides explicit destination project | `testSetProjectIdDoNotOverride` L213-L219 | PORT |  | |
| U.WriteChannelConfiguration.03 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L123-L142; `testOf` L144-L152; `testToBuilderIncomplete` L154-L158; `testBuilder` L160-L202 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `QueryStageTest` — [QueryStageTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/QueryStageTest.java) (5 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.QueryStage.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L140-L149 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.QueryStage.02 | Builder / toBuilder / equals / factory mechanics | `testQueryStepConstructor` L98-L104; `testBuilder` L106-L138; `testEquals` L151-L156; `testNotEquals` L158-L162 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `TimelineSampleTest` — [TimelineSampleTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TimelineSampleTest.java) (3 tests; PORT 0 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.TimelineSample.01 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L40-L44; `testTimelineSampleBuilder` L46-L53; `TestEquals` L55-L61 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `DmlStatsTest` — [DmlStatsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/DmlStatsTest.java) (2 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.DmlStats.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L42-L45 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.DmlStats.02 | Builder / toBuilder / equals / factory mechanics | `testBuilder` L35-L40 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `TableResultTest` — [TableResultTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TableResultTest.java) (5 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.TableResult.01 | Rows without schema accessible by index only | `testNullSchema` L66-L93 | PORT |  | |
| U.TableResult.02 | Rows with schema accessible by name; totalRows/schema exposed | `testSchema` L95-L129 | PORT |  | |
| U.TableResult.03 | statementType and execution stats exposed on result | `testStatementTypeAndExecutionStats` L131-L176 | PORT |  | |
| U.TableResult.04 | Builder / equals / hashCode | `testToBuilder` L178-L206; `testEqualsAndHashCode` L208-L262 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

### 2.4 Values, schema, parameters, insertAll


#### `FieldValueTest` — [FieldValueTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/FieldValueTest.java) (6 tests; PORT 4 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.FieldValue.01 | Cell parsing: BOOL, INT64 (string), FLOAT, GEOGRAPHY, NUMERIC, STRING, TIMESTAMP (seconds->micros), INTERVAL (ISO & canonical), BYTES (base64), RANGE, null, REPEATED, RECORD | `testFromPb` L67-L125 | PORT |  | |
| U.FieldValue.02 | Float-seconds timestamp string (incl. negative/exponent) -> micros | `testTimestamp` L127-L133 | PORT |  | |
| U.FieldValue.03 | useInt64Timestamp lossless micros equals lossy parse; max timestamp 9999-12-31 exact | `testInt64Timestamp` L135-L152; `testLosslessMaxTimestamp` L154-L164 | PORT |  | |
| U.FieldValue.04 | Canonical INTERVAL 'Y-M D H:M:S.f' parsing incl. negatives and extremes | `testParseCanonicalInterval` L220-L236 | PORT |  | |
| U.FieldValue.05 | equals/hashCode | `testEquals` L166-L218 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `FieldValueListTest` — [FieldValueListTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/FieldValueListTest.java) (5 tests; PORT 3 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.FieldValueList.01 | Row parsing against schema | `testFromPb` L141-L152 | PORT |  | |
| U.FieldValueList.02 | Access by index and by field name | `testGetByIndex` L154-L174; `testGetByName` L176-L196 | PORT |  | |
| U.FieldValueList.03 | Name access without schema fails; unknown field fails | `testNullSchema` L198-L220; `testGetNonExistentField` L222-L227 | PORT | Swift: throws / nil. | |

#### `FieldTest` — [FieldTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/FieldTest.java) (12 tests; PORT 2 / ADAPT 0 / N/A 2 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Field.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L181-L188; `testToAndFromPbWithStandardSQLTypeName` L190-L199 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.Field.02 | timestampPrecision only accepts 6 or 12 | `setTimestampPrecisionValues` L217-L229 | PORT |  | |
| U.Field.03 | RECORD type survives Java deserialization clone | `testSubFieldWithClonedType` L201-L215 | N/A | Java Serializable. | |
| U.Field.04 | Builder / toBuilder / equals / factory mechanics | 8 tests in L90-L179 (`testToBuilder, testToBuilderWithStandardSQLTypeName, testToBuilderIncomplete, testToBuilderIncompleteWithStandardSQLTypeName, testToBuilderIncompleteStandard, testToBuilderIncompleteStandardWithStandardSQLTypeName, testBuilder, testBuilderWithStandardSQLTypeName`) | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `FieldListTest` — [FieldListTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/FieldListTest.java) (4 tests; PORT 4 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.FieldList.01 | Field lookup by name is case-insensitive; unknown name fails | `testGetByName` L66-L83 | PORT |  | |
| U.FieldList.02 | Field lookup by index | `testGetByIndex` L85-L96 | PORT |  | |
| U.FieldList.03 | Nested RECORD sub-schema access | `testGetRecordSchema` L98-L115 | PORT |  | |
| U.FieldList.04 | JSON round trip | `testToAndFromPb` L117-L123 | PORT |  | |

#### `SchemaTest` — [SchemaTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/SchemaTest.java) (3 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Schema.01 | TableSchema JSON round trip | `testToAndFromPb` L60-L63 | PORT |  | |
| U.Schema.02 | Empty TableSchema -> zero fields | `testEmptySchema` L70-L75 | PORT |  | |
| U.Schema.03 | Factory | `testOf` L55-L58 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `QueryParameterValueTest` — [QueryParameterValueTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/QueryParameterValueTest.java) (41 tests; PORT 10 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.QueryParameterValue.01 | Builder / required type | `testBuilder` L46-L56; `testTypeNullPointerException` L58-L65 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |
| U.QueryParameterValue.02 | Scalar params: BOOL, INT64 (from long/int), FLOAT64 (double/float), NUMERIC, STRING, GEOGRAPHY, BYTES (base64) value+type | 9 tests in L67-L225 (`testBool, testInt64, testInt64FromInteger, testFloat64, testFloat64FromFloat, testNumeric, testString, testGeography, testBytes`) | PORT |  | |
| U.QueryParameterValue.03 | BIGNUMERIC string formatting (38 digits, scientific for tiny/huge) | `testBigNumeric` L121-L162 | PORT |  | |
| U.QueryParameterValue.04 | JSON param (string / object) | `testJson` L182-L198 | PORT |  | |
| U.QueryParameterValue.05 | INTERVAL param from canonical string / ISO / PeriodDuration | `testInterval` L200-L216 | PORT | Swift: own interval type or string. | |
| U.QueryParameterValue.06 | ARRAY params of each scalar type; empty array keeps element type | 8 tests in L227-L512 (`testBoolArray, testInt64Array, testInt64ArrayFromIntegers, testFloat64Array, testFloat64ArrayFromFloats, testNumericArray, testStringArray, testFromEmptyArray`) | PORT |  | |
| U.QueryParameterValue.07 | TIMESTAMP param from micros/strings/formatters -> 'yyyy-MM-dd HH:mm:ss.SSSSSSZZ' | `testTimestampFromLong` L301-L306; `testTimestampWithFormatter` L308-L317; `testTimestampFromString` L319-L346; `testTimestampWithDateTimeFormatterBuilder` L348-L359 | ADAPT | Swift: from Date/micros/string; same canonical output. | |
| U.QueryParameterValue.08 | Invalid TIMESTAMP strings rejected | `testInvalidTimestampStringValues` L361-L386 | PORT |  | |
| U.QueryParameterValue.09 | DATE/TIME/DATETIME params (incl. java.util.Date) and invalid values rejected | 7 tests in L388-L446 (`testDate, testStandardDate, testInvalidDate, testTime, testInvalidTime, testDateTime, testInvalidDateTime`) | PORT |  | |
| U.QueryParameterValue.10 | TIMESTAMP array params | `testTimestampArrayFromLongs` L448-L460; `testTimestampArray` L462-L475; `testTimestampArrayWithDateTimeFormatterBuilder` L477-L498 | PORT |  | |
| U.QueryParameterValue.11 | STRUCT, nested STRUCT, ARRAY<STRUCT> params (type + value JSON) | `testStruct` L514-L538; `testNestedStruct` L540-L574; `testStructArray` L576-L616 | PORT |  | |
| U.QueryParameterValue.12 | RANGE<DATE\|DATETIME\|TIMESTAMP> param | `testRange` L632-L667 | PORT |  | |

#### `RangeTest` — [RangeTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/RangeTest.java) (4 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Range.01 | Range.of parses '[start, end)' incl. UNBOUNDED/NULL bounds | `testOf` L46-L55 | PORT |  | |
| U.Range.02 | getValues exposes start/end | `testGetValues` L81-L90 | PORT |  | |
| U.Range.03 | Builder mechanics | `testBuilder` L57-L72; `testToBuilder` L74-L79 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `FieldElementTypeTest` — [FieldElementTypeTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/FieldElementTypeTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.FieldElementType.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testFromAndPb` L37-L45 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.FieldElementType.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L27-L30; `testBuilder` L32-L35 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `StandardSQLDataTypeTest` — [StandardSQLDataTypeTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/StandardSQLDataTypeTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.StandardSQLDataType.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L60-L64 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.StandardSQLDataType.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L44-L50; `testBuilder` L52-L58 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `StandardSQLFieldTest` — [StandardSQLFieldTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/StandardSQLFieldTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.StandardSQLField.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L47-L51 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.StandardSQLField.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L34-L38; `testBuilder` L40-L45 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `StandardSQLStructTypeTest` — [StandardSQLStructTypeTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/StandardSQLStructTypeTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.StandardSQLStructType.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L48-L51 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.StandardSQLStructType.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L37-L40; `testBuilder` L42-L46 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `StandardSQLTableTypeTest` — [StandardSQLTableTypeTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/StandardSQLTableTypeTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.StandardSQLTableType.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L49-L52 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.StandardSQLTableType.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L38-L41; `testBuilder` L43-L47 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `InsertAllRequestTest` — [InsertAllRequestTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/InsertAllRequestTest.java) (5 tests; PORT 1 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.InsertAllRequest.01 | Request carries rows (with/without insertId), skipInvalidRows, ignoreUnknownValues, templateSuffix | `testBuilder` L120-L177; `testOf` L179-L203 | ADAPT | Builder/factories -> Swift struct init; test resulting JSON. | |
| U.InsertAllRequest.02 | Row content may contain null values | `testNullOK` L225-L230 | PORT |  | |
| U.InsertAllRequest.03 | equals / immutability | `testEquals` L205-L216; `testImmutable` L218-L223 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `InsertAllResponseTest` — [InsertAllResponseTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/InsertAllResponseTest.java) (4 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.InsertAllResponse.01 | errorsFor(index) and hasErrors | `testErrorsFor` L50-L56; `testHasErrors` L58-L62 | PORT |  | |
| U.InsertAllResponse.02 | insertErrors JSON round trip | `testToPbAndFromPb` L64-L70 | PORT |  | |
| U.InsertAllResponse.03 | Constructor | `testConstructor` L45-L48 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `PolicyTagsTest` — [PolicyTagsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/PolicyTagsTest.java) (5 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.PolicyTags.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testFromAndPb` L57-L60 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.PolicyTags.02 | policyTags without names decodes to nil | `testWithoutNames` L50-L55 | PORT |  | |
| U.PolicyTags.03 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L32-L35; `testToBuilderIncomplete` L37-L42; `testBuilder` L44-L48 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `UserDefinedFunctionTest` — [UserDefinedFunctionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/UserDefinedFunctionTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.UserDefinedFunction.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L45-L49 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.UserDefinedFunction.02 | Builder / toBuilder / equals / factory mechanics | `testConstructor` L31-L37; `testFactoryMethod` L39-L43 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

### 2.5 Resources: datasets, tables, models, routines, ACL, IDs


#### `AclTest` — [AclTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/AclTest.java) (10 tests; PORT 2 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Acl.01 | ACL entity kinds map to/from JSON: dataset, domain, group, specialGroup, user, view, routine, iamMember | 8 tests in L38-L122 (`testDatasetEntity, testDomainEntity, testGroupEntity, testSpecialGroupEntity, testUserEntity, testViewEntity, testRoutineEntity, testIamMemberEntity`) | PORT | Swift: enum with associated values. | |
| U.Acl.02 | Acl(entity, role) and conditional ACL (IAM condition) | `testOf` L124-L139; `testOfWithCondition` L141-L148 | PORT |  | |

#### `DatasetIdTest` — [DatasetIdTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/DatasetIdTest.java) (4 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.DatasetId.01 | ID factory with/without project | `testOf` L28-L34 | PORT |  | |
| U.DatasetId.02 | Reference JSON round trip | `testToPbAndFromPb` L42-L46 | PORT |  | |
| U.DatasetId.03 | setProjectId fills missing project | `testSetProjectId` L48-L51 | PORT |  | |
| U.DatasetId.04 | equals/hashCode | `testEquals` L36-L40 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `DatasetInfoTest` — [DatasetInfoTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/DatasetInfoTest.java) (8 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.DatasetInfo.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L232-L240; `testToBuilderWithExternalDatasetReference` L130-L149 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.DatasetInfo.02 | setProjectId propagates project into dataset reference and ACL entity references | `testSetProjectId` L242-L245 | PORT |  | |
| U.DatasetInfo.03 | maxTimeTravelHours settable/serialized | `testSetMaxTimeTravelHours` L247-L255 | PORT |  | |
| U.DatasetInfo.04 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L106-L122; `testToBuilderIncomplete` L124-L128; `testBuilder` L151-L189; `testOf` L191-L230 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `DatasetTest` — [DatasetTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/DatasetTest.java) (22 tests; PORT 2 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Dataset.01 | Builder / toBuilder / bigquery accessor | `testBuilder` L110-L144; `testToBuilder` L146-L149; `testBigQuery` L325-L328 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |
| U.Dataset.02 | Live-object ops: exists, reload, update, delete, list tables, get table, create table (with options) | 16 tests in L151-L323 (`testExists_True, testExists_False, testReload, testReloadNull, testReloadWithOptions, testUpdate, testUpdateWithOptions, testDeleteTrue, testDeleteFalse, testList, testListWithOptions, testGet, testGetNull, testGetWithOptions, testCreateTable, testCreateTableWithOptions`) | ADAPT | Java 'live object' convenience method delegating to BigQuery; Swift exposes the operation on the client (or a thin wrapper) - test the client call. | |
| U.Dataset.03 | Getting a table from a dataset in another project uses the dataset's project | `testGetTableWithNewProjectId` L277-L285 | PORT |  | |
| U.Dataset.04 | Dataset JSON round trip incl. externalDatasetReference | `testToAndFromPb` L330-L333; `testExternalDatasetReference` L335-L361 | PORT |  | |

#### `TableIdTest` — [TableIdTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TableIdTest.java) (4 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.TableId.01 | ID factory with/without project | `testOf` L30-L39 | PORT |  | |
| U.TableId.02 | Reference JSON round trip | `testToPbAndFromPb` L47-L51 | PORT |  | |
| U.TableId.03 | setProjectId fills missing project | `testSetProjectId` L53-L57 | PORT |  | |
| U.TableId.04 | equals/hashCode | `testEquals` L41-L45 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `TableInfoTest` — [TableInfoTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TableInfoTest.java) (7 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.TableInfo.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L268-L273 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.TableInfo.02 | setProjectId fills project but never overrides an explicit one | `testSetProjectId` L275-L280; `testSetProjectIdDoNotOverride` L282-L287 | PORT |  | |
| U.TableInfo.03 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L155-L164; `testToBuilderIncomplete` L166-L174; `testBuilder` L176-L223; `testOf` L225-L266 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `TableTest` — [TableTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TableTest.java) (23 tests; PORT 1 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Table.01 | Builder / toBuilder / bigquery accessor | `testBuilder` L112-L144; `testToBuilder` L146-L149; `testBigQuery` L347-L350 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |
| U.Table.02 | Live-object ops: exists, reload, update, delete, insert rows, list rows, copy, load, extract | 19 tests in L151-L345 | ADAPT | Java 'live object' convenience method delegating to BigQuery; Swift exposes the operation on the client (or a thin wrapper) - test the client call. Copy/load/extract build the right job configuration. | |
| U.Table.03 | Table JSON round trip | `testToAndFromPb` L352-L355 | PORT |  | |

#### `ModelIdTest` — [ModelIdTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ModelIdTest.java) (4 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ModelId.01 | ID factory with/without project | `testOf` L28-L37 | PORT |  | |
| U.ModelId.02 | Reference JSON round trip | `testToPbAndFromPb` L45-L49 | PORT |  | |
| U.ModelId.03 | setProjectId fills missing project | `testSetProjectId` L51-L55 | PORT |  | |
| U.ModelId.04 | equals/hashCode | `testEquals` L39-L43 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ModelInfoTest` — [ModelInfoTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ModelInfoTest.java) (6 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ModelInfo.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L100-L103 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ModelInfo.02 | setProjectId fills model reference project | `testSetProjectId` L105-L108 | PORT |  | |
| U.ModelInfo.03 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L59-L62; `testToBuilderIncomplete` L64-L68; `testBuilder` L70-L81; `testOf` L83-L98 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ModelTest` — [ModelTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ModelTest.java) (10 tests; PORT 0 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Model.01 | Builder / toBuilder | `testBuilder` L69-L82; `testToBuilder` L84-L87 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |
| U.Model.02 | Live-object ops: exists, reload, update, delete | 8 tests in L89-L153 (`testExists_True, testExists_False, testReload, testReloadNull, testUpdate, testUpdateWithOptions, testDeleteTrue, testDeleteFalse`) | ADAPT | Java 'live object' convenience method delegating to BigQuery; Swift exposes the operation on the client (or a thin wrapper) - test the client call. | |

#### `RoutineIdTest` — [RoutineIdTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/RoutineIdTest.java) (4 tests; PORT 3 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.RoutineId.01 | ID factory with/without project | `testOf` L27-L36 | PORT |  | |
| U.RoutineId.02 | Reference JSON round trip | `testToPbAndFromPb` L44-L48 | PORT |  | |
| U.RoutineId.03 | setProjectId fills missing project | `testSetProjectId` L50-L54 | PORT |  | |
| U.RoutineId.04 | equals/hashCode | `testEquals` L38-L42 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `RoutineInfoTest` — [RoutineInfoTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/RoutineInfoTest.java) (6 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.RoutineInfo.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L116-L119 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.RoutineInfo.02 | setProjectId fills routine reference project | `testSetProjectId` L121-L124 | PORT |  | |
| U.RoutineInfo.03 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L70-L73; `testBuilderIncomplete` L75-L79; `testBuilder` L81-L96; `testOf` L98-L114 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `RoutineTest` — [RoutineTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/RoutineTest.java) (10 tests; PORT 0 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.Routine.01 | Builder / toBuilder | `testBuilder` L133-L153; `testToBuilder` L155-L159 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |
| U.Routine.02 | Live-object ops: exists, reload, update, delete | 8 tests in L161-L226 (`testExists_True, testExists_False, testReload, testReload_Null, testUpdate, testUpdateWithOptions, testDeleteTrue, testDeleteFalse`) | ADAPT | Java 'live object' convenience method delegating to BigQuery; Swift exposes the operation on the client (or a thin wrapper) - test the client call. | |

#### `RoutineArgumentTest` — [RoutineArgumentTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/RoutineArgumentTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.RoutineArgument.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L50-L53 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.RoutineArgument.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L37-L40; `testBuilder` L42-L48 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `RemoteFunctionOptionsTest` — [RemoteFunctionOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/RemoteFunctionOptionsTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.RemoteFunctionOptions.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L59-L63 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.RemoteFunctionOptions.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L45-L49; `testBuilder` L51-L57 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ExternalDatasetReferenceTest` — [ExternalDatasetReferenceTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ExternalDatasetReferenceTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ExternalDatasetReference.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L54-L63 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ExternalDatasetReference.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L33-L40; `testBuilder` L42-L52 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

### 2.6 Table definitions, external formats, constraints, partitioning


#### `StandardTableDefinitionTest` — [StandardTableDefinitionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/StandardTableDefinitionTest.java) (9 tests; PORT 2 / ADAPT 1 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.StandardTableDefinition.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L161-L170 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.StandardTableDefinition.02 | Unknown timePartitioning.type is rejected with descriptive error | `testFromPbWithUnexpectedTimePartitioningTypeRaisesInvalidArgumentException` L172-L190 | ADAPT | Swift should prefer tolerant decoding (unknown enum value preserved); document divergence. | |
| U.StandardTableDefinition.03 | streamingBuffer with null estimatedRows/Bytes/oldestEntryTime decodes and encodes | `testFromPbWithNullEstimatedRowsAndBytes` L192-L196; `testStreamingBufferWithNullFieldsToPb` L198-L201 | PORT |  | |
| U.StandardTableDefinition.04 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L95-L103; `testToBuilderIncomplete` L105-L109; `testBuilder` L111-L130; `testTypeNullPointerException` L132-L138; `testOf` L140-L159 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ExternalTableDefinitionTest` — [ExternalTableDefinitionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ExternalTableDefinitionTest.java) (6 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ExternalTableDefinition.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L156-L165; `testToAndFromPbParquet` L167-L176 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ExternalTableDefinition.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L99-L116; `testToBuilderIncomplete` L118-L123; `testTypeNullPointerException` L125-L130; `testBuilder` L132-L154 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `MaterializedViewDefinitionTest` — [MaterializedViewDefinitionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/MaterializedViewDefinitionTest.java) (4 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.MaterializedViewDefinition.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L84-L94 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.MaterializedViewDefinition.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L47-L57; `testToBuilderIncomplete` L59-L64; `testBuilder` L66-L82 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ViewDefinitionTest` — [ViewDefinitionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ViewDefinitionTest.java) (5 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ViewDefinition.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L105-L111 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ViewDefinition.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L38-L49; `testTypeNullPointerException` L51-L57; `testToBuilderIncomplete` L59-L63; `testBuilder` L65-L103 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `SnapshotTableDefinitionTest` — [SnapshotTableDefinitionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/SnapshotTableDefinitionTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.SnapshotTableDefinition.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L56-L64 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.SnapshotTableDefinition.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L34-L41; `testBuilder` L43-L54 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `CloneDefinitionTest` — [CloneDefinitionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/CloneDefinitionTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.CloneDefinition.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L47-L52 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.CloneDefinition.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L30-L36; `testBuilder` L38-L45 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ModelTableDefinitionTest` — [ModelTableDefinitionTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ModelTableDefinitionTest.java) (7 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ModelTableDefinition.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L74-L78 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ModelTableDefinition.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L54-L57; `testTypeNullPointerException` L59-L66; `testToBuilderIncomplete` L68-L72; `testBuilder` L80-L86; `testEquals` L88-L91; `testNotEquals` L93-L96 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `TableConstraintsTest` — [TableConstraintsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TableConstraintsTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.TableConstraints.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L105-L111 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.TableConstraints.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L52-L90; `testBuilder` L92-L103 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `TableMetadataCacheUsageTest` — [TableMetadataCacheUsageTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TableMetadataCacheUsageTest.java) (1 tests; PORT 1 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.TableMetadataCacheUsage.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L53-L58 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |

#### `AvroOptionsTest` — [AvroOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/AvroOptionsTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.AvroOptions.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L44-L50 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.AvroOptions.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L29-L36; `testBuilder` L38-L42 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `BigtableOptionsTest` — [BigtableOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/BigtableOptionsTest.java) (5 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.BigtableOptions.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L120-L125 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.BigtableOptions.02 | Builder / toBuilder / equals / factory mechanics | `testConstructors` L57-L80; `testNullPointerException` L82-L109; `testIllegalStateException` L111-L118; `testEquals` L127-L136 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `CsvOptionsTest` — [CsvOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/CsvOptionsTest.java) (4 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.CsvOptions.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L77-L82 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.CsvOptions.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L48-L55; `testToBuilderIncomplete` L57-L61; `testBuilder` L63-L75 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `DatastoreBackupOptionsTest` — [DatastoreBackupOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/DatastoreBackupOptionsTest.java) (3 tests; PORT 0 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.DatastoreBackupOptions.01 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L31-L40; `testToBuilderIncomplete` L42-L47; `testBuilder` L49-L53 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `FormatOptionsTest` — [FormatOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/FormatOptionsTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.FormatOptions.01 | Source format strings and factories (csv, json=NEWLINE_DELIMITED_JSON, datastoreBackup, avro, googleSheets, iceberg, ...) | `testConstructor` L25-L35; `testFactoryMethods` L37-L45 | PORT | Swift: enum raw values. | |
| U.FormatOptions.02 | equals | `testEquals` L47-L58 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `GoogleSheetsOptionsTest` — [GoogleSheetsOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/GoogleSheetsOptionsTest.java) (4 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.GoogleSheetsOptions.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L76-L89 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.GoogleSheetsOptions.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L35-L59; `testToBuilderIncomplete` L61-L65; `testBuilder` L67-L74 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `HivePartitioningOptionsTest` — [HivePartitioningOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/HivePartitioningOptionsTest.java) (4 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.HivePartitioningOptions.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L63-L68 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.HivePartitioningOptions.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L39-L47; `testToBuilderIncomplete` L49-L53; `testBuilder` L55-L61 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ParquetOptionsTest` — [ParquetOptionsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ParquetOptionsTest.java) (4 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ParquetOptions.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L61-L67 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ParquetOptions.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L33-L44; `testToBuilderIncomplete` L46-L51; `testBuilder` L53-L59 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `BigLakeConfigurationTest` — [BigLakeConfigurationTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/BigLakeConfigurationTest.java) (5 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.BigLakeConfiguration.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPb` L54-L57; `testFromPb` L59-L63 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.BigLakeConfiguration.02 | Null fields encode/decode as absent | `testNullFields` L65-L72; `testFromPbWithNullFields` L74-L83 | PORT |  | |
| U.BigLakeConfiguration.03 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L46-L52 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ColumnReferenceTest` — [ColumnReferenceTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ColumnReferenceTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ColumnReference.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L56-L62 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ColumnReference.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L31-L41; `testBuilder` L43-L54 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `ForeignKeyTest` — [ForeignKeyTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/ForeignKeyTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.ForeignKey.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L82-L87 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.ForeignKey.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L41-L65; `testBuilder` L67-L80 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `PrimaryKeyTest` — [PrimaryKeyTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/PrimaryKeyTest.java) (3 tests; PORT 1 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.PrimaryKey.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L45-L50 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.PrimaryKey.02 | Builder / toBuilder / equals / factory mechanics | `testToBuilder` L30-L36; `testBuilder` L38-L43 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `TimePartitioningTest` — [TimePartitioningTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/TimePartitioningTest.java) (5 tests; PORT 2 / ADAPT 0 / N/A 1 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.TimePartitioning.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToAndFromPb` L106-L112 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |
| U.TimePartitioning.02 | TimePartitioning.of(type[, expirationMs]) for DAY/HOUR/MONTH/YEAR | `testOf` L62-L74 | PORT |  | |
| U.TimePartitioning.03 | Builder / toBuilder / equals / factory mechanics | `testBuilder` L76-L90; `testTypeOf_Npe` L92-L97; `testTypeAndExpirationOf_Npe` L99-L104 | N/A | Java builder/toBuilder/equals mechanics; Swift value types with memberwise init + synthesized Equatable. | |

#### `MetadataCacheStatsTest` — [MetadataCacheStatsTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/MetadataCacheStatsTest.java) (1 tests; PORT 1 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Behavior pinned down | Java test(s) & lines | Class | Notes | Swift test |
|---|---|---|---|---|---|
| U.MetadataCacheStats.01 | REST JSON round trip preserves every field (toPb/fromPb) | `testToPbAndFromPb` L46-L51 | PORT | Swift: Codable encode/decode round trip against JSON fixture. | |

## 3. Integration test baseline

Fixture abbreviations are defined in [§4](#4-fixtures-and-the-test-project).


### 3.1 `ITBigQueryTest` — [it/ITBigQueryTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/it/ITBigQueryTest.java) (193 tests; PORT 143 / ADAPT 11 / N/A 0 / DEFERRED 39)

| ID | Test (lines) | Feature exercised | Resources / fixtures | Class | Notes | Swift test |
|---|---|---|---|---|---|---|
| IT-001 | `testLosslessMaxTimestampIntegration` (L1236-L1284) | Max TIMESTAMP 9999-12-31 round-trips losslessly with int64 timestamps | none (literal SQL) | PORT |  | |
| IT-002 | `testListDatasets` (L1286-L1302) | datasets.list on another project returns names + locations | PUB (project listing), G | PORT | Read-only public project; works from any project. | |
| IT-003 | `testListDatasetsWithFilter` (L1304-L1319) | datasets.list labelFilter | D (labels) | PORT |  | |
| IT-004 | `testGetDataset` (L1321-L1333) | datasets.get fields (description, labels, etag, times, location) | D | PORT |  | |
| IT-005 | `testDatasetUpdateAccess` (L1335-L1348) | Dataset ACL update (group/user/iamMember allUsers) | D; caller's service-account email | ADAPT | Needs SA client email; allUsers READER may be blocked by org policy (domain-restricted sharing) - use a group or skip-if-forbidden. | |
| IT-006 | `testGetDatasetWithSelectedFields` (L1350-L1370) | datasets.get with field mask -> unselected fields null | D | PORT |  | |
| IT-007 | `testGetDatasetWithAccessPolicyVersion` (L1372-L1414) | datasets.get accessPolicyVersion=3 returns conditional ACL | NEWDS; IAM condition on caller | ADAPT | Conditional ACL requires principal email; parameterize. | |
| IT-008 | `testUpdateDataset` (L1416-L1456) | datasets.patch description/labels/storageBillingModel/maxTimeTravelHours; setting labels to null clears them | NEWDS | PORT | Pins clearing labels via JSON null. | |
| IT-009 | `testUpdateDatasetWithSelectedFields` (L1458-L1488) | datasets.patch with field mask | NEWDS | PORT |  | |
| IT-010 | `testUpdateDatasetWithAccessPolicyVersion` (L1490-L1541) | datasets.patch with accessPolicyVersion + conditional ACL | NEWDS; IAM condition on caller | ADAPT | As above. | |
| IT-011 | `testGetNonExistingTable` (L1543-L1546) | tables.get missing -> null | D | PORT | Swift: nil/notFound per design. | |
| IT-012 | `testCreateTableWithRangePartitioning` (L1548-L1570) | Create table with RANGE partitioning | D | PORT |  | |
| IT-013 | `testJsonType` (L1573-L1679) | JSON column: insertAll, query, JSON query params, invalid JSON error | D (per-test table) | PORT |  | |
| IT-014 | `testIntervalType` (L1682-L1755) | INTERVAL column: DML insert, insertAll, list/query values | D (per-test table) | PORT |  | |
| IT-015 | `testRangeType` (L1757-L1832) | RANGE<DATE/DATETIME/TIMESTAMP> column: insertAll, list, query params | D (per-test table) | PORT |  | |
| IT-016 | `testCreateTableWithConstraints` (L1834-L1876) | Table with primary/foreign key constraints | D | PORT |  | |
| IT-017 | `testCreateDatasetWithSpecifiedStorageBillingModel` (L1878-L1893) | Dataset storageBillingModel=LOGICAL | NEWDS | PORT |  | |
| IT-018 | `testCreateDatasetWithSpecificMaxTimeTravelHours` (L1895-L1910) | Dataset maxTimeTravelHours=120 | NEWDS | PORT |  | |
| IT-019 | `testCreateDatasetWithDefaultMaxTimeTravelHours` (L1912-L1927) | Dataset default maxTimeTravelHours=168 | NEWDS | PORT |  | |
| IT-020 | `testCreateDatasetWithDefaultCollation` (L1929-L1944) | Dataset defaultCollation | NEWDS | PORT |  | |
| IT-021 | `testCreateDatasetWithAccessPolicyVersion` (L1946-L1981) | datasets.insert with accessPolicyVersion + conditional ACL | NEWDS; IAM condition on caller | ADAPT | Parameterize principal. | |
| IT-022 | `testCreateDatasetWithInvalidAccessPolicyVersion` (L1983-L2007) | Invalid accessPolicyVersion -> 400 error surfaced | NEWDS | PORT |  | |
| IT-023 | `testCreateTableWithDefaultCollation` (L2009-L2045) | Table defaultCollation propagates to STRING fields | D | PORT |  | |
| IT-024 | `testCreateFieldWithDefaultCollation` (L2047-L2082) | Field-level collation | D | PORT |  | |
| IT-025 | `testCreateTableWithDefaultValueExpression` (L2084-L2144) | Field defaultValueExpression applied on insert | D (DML/insert + list) | PORT |  | |
| IT-026 | `testCreateAndGetTable` (L2146-L2182) | tables.insert + get round trip (schema, partitioning, stats) | D | PORT |  | |
| IT-027 | `testCreateAndListTable` (L2184-L2217) | tables.insert + list finds table | D | PORT |  | |
| IT-028 | `testCreateAndGetTableWithBasicTableMetadataView` (L2219-L2249) | tables.get view=BASIC omits storage stats | D | PORT |  | |
| IT-029 | `testCreateAndGetTableWithFullTableMetadataView` (L2251-L2280) | tables.get view=FULL | D | PORT |  | |
| IT-030 | `testCreateAndGetTableWithStorageStatsTableMetadataView` (L2282-L2312) | tables.get view=STORAGE_STATS | D | PORT |  | |
| IT-031 | `testCreateAndGetTableWithUnspecifiedTableMetadataView` (L2314-L2344) | tables.get view=TABLE_METADATA_VIEW_UNSPECIFIED | D | PORT |  | |
| IT-032 | `testCreateAndGetTableWithSelectedField` (L2346-L2384) | tables.get field mask | D | PORT |  | |
| IT-033 | `testCreateExternalTable` (L2386-L2442) | External JSON table over GCS + query it | D, B (load.json) | PORT | Uses the temp bucket (§4.1 B). | |
| IT-034 | `testSetPermExternalTableSchema` (L2444-L2470) | External table with BigLake connection + explicit schema | G; B; connection projects/java-docs-samples-testing/locations/us/connections/DEVREL_TEST_CONNECTION; US dataset | ADAPT | Foreign-project connection: gate on env BIGQUERY_TEST_CONNECTION_ID (our runs: us.test-connection-id-ace13f7e; its SA needs GCS read on the temp bucket); skip when unset. | |
| IT-035 | `testUpdatePermExternableTableWithAutodetectSchemaUpdatesSchema` (L2472-L2505) | tables.patch autodetect_schema=true updates external table schema | D, B | PORT |  | |
| IT-036 | `testCreateViewTable` (L2507-L2553) | Create logical view + query it | D, T | PORT |  | |
| IT-037 | `testCreateMaterializedViewTable` (L2555-L2578) | Create materialized view | D, T | PORT |  | |
| IT-038 | `testTableIAM` (L2580-L2607) | tables testIamPermissions/getIamPolicy/setIamPolicy | D (per-test table); setIamPolicy permission | ADAPT | Uses allUsers dataViewer - may violate org policy; use a group/SA member. | |
| IT-039 | `testListTables` (L2609-L2626) | tables.list | D | PORT |  | |
| IT-040 | `testListTablesWithPartitioning` (L2628-L2669) | tables.list surfaces timePartitioning | D | PORT |  | |
| IT-041 | `testListTablesWithRangePartitioning` (L2671-L2708) | tables.list surfaces rangePartitioning | D | PORT |  | |
| IT-042 | `testListPartitions` (L2710-L2734) | listPartitions on DAY-partitioned table after DML | D | PORT |  | |
| IT-043 | `testUpdateTable` (L2736-L2764) | tables.patch description/labels | D | PORT |  | |
| IT-044 | `testUpdateTimePartitioning` (L2766-L2807) | Update/remove partition expiration (null expiration) | D | PORT | Pins explicit-null patching. | |
| IT-045 | `testUpdateNonExistingTable` (L2839-L2854) | tables.patch missing table -> 404 error (notFound) | D | PORT |  | |
| IT-046 | `testDeleteNonExistingTable` (L2856-L2859) | tables.delete missing -> false | none | PORT |  | |
| IT-047 | `testDeleteJob` (L2861-L2873) | jobs.delete with location us-east1; get after delete -> null | G; job in us-east1 | PORT |  | |
| IT-048 | `testInsertAll` (L2875-L2934) | insertAll all types incl. nested/repeated, no errors | D (per-test table) | PORT |  | |
| IT-049 | `testInsertAllWithSuffix` (L2936-L3004) | insertAll templateSuffix creates suffixed table | D | PORT | Template tables can take time to appear; poll. | |
| IT-050 | `testInsertAllWithErrors` (L3006-L3075) | insertAll per-row errors with skipInvalidRows/ignoreUnknownValues | D | PORT |  | |
| IT-051 | `testListAllTableData` (L3078-L3121) | tabledata.list full table + field types | T | PORT |  | |
| IT-052 | `testListPageWithStartIndex` (L3123-L3140) | tabledata.list startIndex/maxResults on public table | PUB census_bureau_international; G | PORT | Read-only public data. | |
| IT-053 | `testModelLifecycle` (L3142-L3199) | CREATE MODEL via query, get/list/update/delete model | MD | PORT | BQML training (cost/time). | |
| IT-054 | `testEmptyListModels` (L3201-L3210) | models.list on empty dataset -> no page token | per-test dataset | PORT |  | |
| IT-055 | `testEmptyListRoutines` (L3212-L3222) | routines.list on empty dataset -> no page token | per-test dataset | PORT |  | |
| IT-056 | `testRoutineLifecycle` (L3224-L3265) | CREATE FUNCTION via query, get/list/update/delete routine | RD | PORT |  | |
| IT-057 | `testRoutineAPICreation` (L3267-L3287) | routines.insert SQL scalar function | RD | PORT |  | |
| IT-058 | `testRoutineAPICreationJavascriptUDF` (L3289-L3315) | routines.insert JavaScript UDF | RD | PORT |  | |
| IT-059 | `testRoutineAPICreationTVF` (L3317-L3343) | routines.insert table-valued function with returnTableType | RD | PORT |  | |
| IT-060 | `testRoutineDataGovernanceType` (L3345-L3370) | routines.insert dataGovernanceType=DATA_MASKING | RD | PORT |  | |
| IT-061 | `testAuthorizeRoutine` (L3372-L3396) | Authorized routine ACL entry on dataset | RD | PORT |  | |
| IT-062 | `testAuthorizeDataset` (L3398-L3440) | Authorized dataset ACL entry | 2x NEWDS | PORT |  | |
| IT-063 | `testSingleStatementsQueryException` (L3443-L3457) | Failing DML job: error in job status | D, T | PORT |  | |
| IT-064 | `testMultipleStatementsQueryException` (L3460-L3476) | Failing script job: error surfaced | D, T | PORT |  | |
| IT-065 | `testTimestamp` (L3478-L3494) | TIMESTAMP literal query value (micros) | D | PORT |  | |
| IT-066 | `testLosslessTimestamp` (L3496-L3533) | useInt64Timestamp client option: lossless micros | D | PORT |  | |
| IT-067 | `testQuery` (L3536-L3575) | query() over table, iterate rows, jobId present | D, T | PORT |  | |
| IT-068 | `testQueryStatistics` (L3577-L3592) | Query job statistics: queryPlan, totalSlotMs | D | PORT |  | |
| IT-069 | `testExecuteSelectDefaultConnectionSettings` (L3594-L3602) | Connection API executeSelect | PUB samples.shakespeare; G | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-070 | `testExecuteSelectWithReadApi` (L3604-L3632) | executeSelect with Read API | PUB new_york_taxi_trips; G | DEFERRED | Connection API (createConnection/executeSelect) deferred. Storage Read API deferred. | |
| IT-071 | `testExecuteSelectWithFastQueryReadApi` (L3634-L3659) | executeSelect fast query + Read API | PUB new_york_taxi_trips; G | DEFERRED | Connection API (createConnection/executeSelect) deferred. Storage Read API deferred. | |
| IT-072 | `testExecuteSelectReadApiEmptyResultSet` (L3661-L3677) | Read API empty result | none | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-073 | `testExecuteSelectWithCredentials` (L3679-L3720) | executeSelect with explicit credentials | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-074 | `testQueryTimeStamp` (L3723-L3757) | TIMESTAMP query value formats | D | PORT |  | |
| IT-075 | `testQueryCaseInsensitiveSchemaFieldByGetName` (L3760-L3787) | Row access by field name is case-insensitive | D, T | PORT |  | |
| IT-076 | `testQueryExternalHivePartitioningOptionAutoLayout` (L3790-L3823) | External table hive partitioning AUTO + query | D; CSD hive-partitioning-samples/autolayout | PORT | Public bucket readable. | |
| IT-077 | `testQueryExternalHivePartitioningOptionCustomLayout` (L3826-L3860) | External table hive partitioning CUSTOM + query | D; CSD hive-partitioning-samples/customlayout | PORT |  | |
| IT-078 | `testConnectionImplDryRun` (L3862-L3888) | Connection dryRun | D, TRS | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-079 | `testConnectionImplDryRunNoQueryParameters` (L3890-L3916) | Connection dryRun w/o params | D, TRS | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-080 | `testBQResultSetMultiThreadedOrder` (L3918-L3945) | Connection ResultSet ordering | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-081 | `testBQResultSetPaginationSlowQuery` (L3947-L3975) | Connection pagination slow query | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-082 | `testExecuteSelectSinglePageTableRow` (L3977-L4041) | Connection single page typed getters | D, TRS | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-083 | `testExecuteSelectSinglePageTableRowWithReadAPI` (L4043-L4108) | Same with Read API | D, TRS | DEFERRED | Connection API (createConnection/executeSelect) deferred. Storage Read API deferred. | |
| IT-084 | `testConnectionClose` (L4110-L4135) | Connection close | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-085 | `testBQResultSetPagination` (L4137-L4162) | Connection pagination | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-086 | `testReadAPIIterationAndOrder` (L4164-L4200) | Read API iteration order | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. Storage Read API deferred. | |
| IT-087 | `testReadAPIIterationAndOrderAsync` (L4202-L4244) | Read API async iteration | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. Storage Read API deferred. | |
| IT-088 | `testExecuteSelectAsyncCancel` (L4246-L4288) | executeSelectAsync cancel | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-089 | `testExecuteSelectAsyncTimeout` (L4290-L4323) | executeSelectAsync timeout | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-090 | `testExecuteSelectWithNamedQueryParametersAsync` (L4325-L4351) | executeSelectAsync named params | D, T | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-091 | `testCreateDefaultConnection` (L4355-L4360) | createConnection() defaults | none | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-092 | `testReadAPIConnectionMultiClose` (L4362-L4397) | Read API connection multi close | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. Storage Read API deferred. | |
| IT-093 | `testExecuteSelectSinglePageTableRowColInd` (L4399-L4478) | Connection getters by column index | D, TRS | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-094 | `testExecuteSelectStruct` (L4480-L4511) | Connection STRUCT values | D | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-095 | `testExecuteSelectStructSubField` (L4513-L4537) | Connection STRUCT subfield | D | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-096 | `testExecuteSelectArray` (L4539-L4560) | Connection ARRAY values | D | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-097 | `testExecuteSelectArrayOfStruct` (L4562-L4600) | Connection ARRAY<STRUCT> | D | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-098 | `testFastQueryMultipleRuns` (L4603-L4637) | Repeated fast queries: same results, distinct jobIds | D, TFQ | PORT |  | |
| IT-099 | `testFastQuerySinglePageDuplicateRequestIds` (L4640-L4670) | Back-to-back single-page fast queries each return complete results (no requestId collision) | D, TFQ | PORT |  | |
| IT-100 | `testFastSQLQuery` (L4673-L4701) | Fast path SELECT: schema, rows, totalRows, no next page | D, TFQ | PORT |  | |
| IT-101 | `testProjectIDFastSQLQueryWithJobId` (L4703-L4718) | query() with JobId carrying project | D, TFQ | PORT |  | |
| IT-102 | `testLocationFastSQLQueryWithJobId` (L4720-L4787) | query() with JobId location in EU against EU dataset; wrong location fails | UKD (EU) created per test; G | PORT | Multi-region EU dataset creation allowed in test project. | |
| IT-103 | `testFastSQLQueryMultiPage` (L4790-L4821) | Fast path multi-page results (pageSize) | D, TL | PORT |  | |
| IT-104 | `testFastDMLQuery` (L4823-L4854) | Fast path DML: numDmlAffectedRows, empty schema | D, TS | PORT |  | |
| IT-105 | `testFastDDLQuery` (L4856-L4893) | Fast path DDL CREATE OR REPLACE TABLE | D, TS | PORT |  | |
| IT-106 | `testFastQuerySlowDDL` (L4895-L4932) | Slow DDL on fast path falls back to job polling | PUB new_york.311_service_requests; temp US dataset; G | PORT | Scans public data (cost). | |
| IT-107 | `testFastQueryHTTPException` (L4935-L4967) | Invalid query / missing table -> errors reason invalidQuery / notFound | D, TFQ | PORT |  | |
| IT-108 | `testQuerySessionSupport` (L4969-L5000) | createSession=true returns sessionId; reuse via connectionProperties session_id | D | PORT |  | |
| IT-109 | `testLoadSessionSupportWriteChannelConfiguration` (L5002-L5074) | Writer (resumable upload) load into _SESSION temp table | G; US session; local CSV | PORT |  | |
| IT-110 | `testLoadSessionSupport` (L5076-L5125) | GCS load job into session temp table | B (load.csv) | PORT |  | |
| IT-111 | `testExecuteSelectSessionSupport` (L5139-L5151) | Connection API session | D | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-112 | `testDmlStatistics` (L5153-L5188) | DML job statistics (inserted/updated/deleted rows) | D, TS | PORT |  | |
| IT-113 | `testTransactionInfo` (L5191-L5226) | Multi-statement transaction: transactionInfo on child jobs | D, TS | PORT |  | |
| IT-114 | `testScriptStatistics` (L5229-L5280) | Script: numChildJobs, child scriptStatistics (evaluationKind, stack frames), jobs.list by parentJobId | PUB usa_names.usa_1910_current; G | PORT |  | |
| IT-115 | `testQueryParameterModeWithDryRun` (L5282-L5310) | Dry run reports queryParameters (7) and totalBytesProcessed | D, T | PORT |  | |
| IT-116 | `testPositionalQueryParameters` (L5312-L5387) | Positional params of every scalar type incl. BIGNUMERIC/NUMERIC/TIMESTAMP | D, T | PORT |  | |
| IT-117 | `testExecuteSelectWithPositionalQueryParameters` (L5390-L5408) | Connection positional params | D, T | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-118 | `testNamedQueryParameters` (L5410-L5431) | Named params (STRING, INT64, ARRAY) | D, T | PORT |  | |
| IT-119 | `testExecuteSelectWithNamedQueryParameters` (L5433-L5454) | Connection named params | D, T | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-120 | `testStructNamedQueryParameters` (L5457-L5482) | STRUCT named param round trip | D | PORT |  | |
| IT-121 | `testRepeatedRecordNamedQueryParameters` (L5484-L5523) | ARRAY<STRUCT> named param round trip | D | PORT |  | |
| IT-122 | `testUnnestRepeatedRecordNamedQueryParameter` (L5525-L5563) | UNNEST ARRAY<STRUCT> param filter | D | PORT |  | |
| IT-123 | `testUnnestRepeatedRecordNamedQueryParameterFromDataset` (L5565-L5609) | UNNEST ARRAY<STRUCT> param against table data | D (per-test table) | PORT |  | |
| IT-124 | `testEmptyRepeatedRecordNamedQueryParameters` (L5671-L5691) | Empty ARRAY<STRUCT> param -> BigQueryException | D | PORT |  | |
| IT-125 | `testStructQuery` (L5693-L5711) | Query RECORD column values | D, T | PORT |  | |
| IT-126 | `testNestedStructNamedQueryParameters` (L5721-L5760) | Nested STRUCT param | D | PORT |  | |
| IT-127 | `testBytesParameter` (L5763-L5782) | BYTES param | D | PORT |  | |
| IT-128 | `testGeographyParameter` (L5784-L5806) | GEOGRAPHY param | D | PORT |  | |
| IT-129 | `testListJobs` (L5808-L5818) | jobs.list | none | PORT |  | |
| IT-130 | `testListJobsWithSelectedFields` (L5820-L5830) | jobs.list field mask | none | PORT |  | |
| IT-131 | `testListJobsWithCreationBounding` (L5832-L5853) | jobs.list min/maxCreationTime | none | PORT |  | |
| IT-132 | `testCreateAndGetJob` (L5855-L5892) | Copy job create + get | D (per-test tables) | PORT |  | |
| IT-133 | `testCreateJobAndWaitForWithRetryOptions` (L5894-L5911) | jobs.insert + waitFor with BigQueryRetryConfig and RetryOptions(maxAttempts=1), happy path | D | ADAPT | Swift per-call retry/polling options. | |
| IT-134 | `testCreateAndGetJobWithSelectedFields` (L5913-L5961) | jobs.insert/get field masks | D | PORT |  | |
| IT-135 | `testCopyJob` (L5963-L5993) | Copy job | D | PORT |  | |
| IT-136 | `testCopyJobStatistics` (L5995-L6024) | Copy job statistics (copiedRows/bytes) | D | PORT |  | |
| IT-137 | `testSnapshotTableCopyJob` (L6026-L6102) | Snapshot via copy (operationType SNAPSHOT) + restore | D, TS | PORT |  | |
| IT-138 | `testCopyJobWithLabelsAndExpTime` (L6104-L6132) | Copy job labels + destinationExpirationTime | D | PORT |  | |
| IT-139 | `testQueryJob` (L6135-L6178) | Query job with destination table | D, T | PORT |  | |
| IT-140 | `testQueryJobWithConnectionProperties` (L6181-L6198) | Query job connectionProperties (time_zone) | D, T | PORT |  | |
| IT-141 | `testQueryJobWithLabels` (L6201-L6222) | Query job labels | D, T | PORT |  | |
| IT-142 | `testQueryJobWithSearchReturnsSearchStatisticsUnused` (L6224-L6249) | SEARCH() query -> searchStatistics UNUSED | D, T | PORT |  | |
| IT-143 | `testQueryJobWithRangePartitioning` (L6252-L6275) | Query job destination rangePartitioning | D, T | PORT |  | |
| IT-144 | `testLoadJobWithRangePartitioning` (L6277-L6299) | Load job rangePartitioning from GCS | D, B | PORT |  | |
| IT-145 | `testLoadJobWithDecimalTargetTypes` (L6301-L6327) | Load parquet with decimalTargetTypes | D; CSD bigquery/numeric/numeric_38_12.parquet | PORT |  | |
| IT-146 | `testExternalTableWithDecimalTargetTypes` (L6329-L6347) | External parquet table decimalTargetTypes | D; CSD numeric_38_12.parquet | PORT |  | |
| IT-147 | `testQueryJobWithDryRun` (L6349-L6365) | Query job dryRun stats | D, T | PORT |  | |
| IT-148 | `testExtractJob` (L6367-L6405) | Extract table to GCS CSV, read back | D, B (write); storage read | PORT | Needs writable bucket. | |
| IT-149 | `testExtractJobWithModel` (L6407-L6442) | Extract BQML model to GCS | MD, B | PORT | BQML (cost/time). | |
| IT-150 | `testExtractJobWithLabels` (L6444-L6468) | Extract job labels | D, B | PORT |  | |
| IT-151 | `testCancelJob` (L6470-L6482) | jobs.cancel running query | D, T | PORT |  | |
| IT-152 | `testCancelNonExistingJob` (L6484-L6487) | cancel missing job -> false | G | PORT |  | |
| IT-153 | `testInsertFromFile` (L6489-L6560) | Writer (resumable upload) load from local data, then list rows | D | PORT |  | |
| IT-154 | `testInsertFromFileWithLabels` (L6562-L6590) | Writer load with job labels | D | PORT |  | |
| IT-155 | `testInsertWithDecimalTargetTypes` (L6592-L6618) | Writer load with decimalTargetTypes | D | PORT |  | |
| IT-156 | `testLocation` (L6620-L6724) | Location handling: EU dataset; jobs created/fetched/cancelled/queried/written with right vs wrong location | per-test EU dataset; G (OTel-enabled client, incidental) | PORT | Ignore the OTel client wiring. | |
| IT-157 | `testWriteChannelPreserveAsciiControlCharacters` (L6726-L6752) | Writer CSV preserveAsciiControlCharacters | D | PORT |  | |
| IT-158 | `testLoadJobPreserveAsciiControlCharacters` (L6754-L6773) | GCS load preserveAsciiControlCharacters | D, B (load_null.csv) | PORT |  | |
| IT-159 | `testReferenceFileSchemaUriForAvro` (L6775-L6832) | Load AVRO with referenceFileSchemaUri | D; CSD federated-formats-reference-file-schema/*.avro | PORT |  | |
| IT-160 | `testReferenceFileSchemaUriForParquet` (L6834-L6890) | Load PARQUET with referenceFileSchemaUri | D; CSD federated-formats-reference-file-schema/*.parquet | PORT |  | |
| IT-161 | `testCreateExternalTableWithReferenceFileSchemaAvro` (L6892-L6930) | External AVRO table referenceFileSchemaUri | D; CSD (hard-coded cloud-samples-data) | PORT |  | |
| IT-162 | `testCreateExternalTableWithReferenceFileSchemaParquet` (L6932-L6972) | External PARQUET table referenceFileSchemaUri | D; CSD (hard-coded) | PORT |  | |
| IT-163 | `testCloneTableCopyJob` (L6974-L7025) | Clone via copy (operationType CLONE), cloneDefinition | D, TS | PORT |  | |
| IT-164 | `testHivePartitioningOptionsFieldsFieldExistence` (L7027-L7069) | HivePartitioningOptions.fields populated on get | D, B (writes key=foo/data.json) | PORT |  | |
| IT-165 | `testPrimaryKey` (L7071-L7094) | Create table with primary key | D | PORT |  | |
| IT-166 | `testPrimaryKeyUpdate` (L7096-L7123) | Add primary key via update | D | PORT |  | |
| IT-167 | `testForeignKeys` (L7125-L7173) | Create tables with foreign keys | D | PORT |  | |
| IT-168 | `testForeignKeysUpdate` (L7175-L7271) | Add/replace foreign keys via update | D | PORT |  | |
| IT-169 | `testAlreadyExistJobExceptionHandling` (L7273-L7298) | query() with existing JobId recovers from 409 Already Exists | D, T | PORT |  | |
| IT-170 | `testStatelessQueries` (L7300-L7325) | JOB_CREATION_OPTIONAL: queryId set, jobId null for short queries | own client | PORT |  | |
| IT-171 | `testTableResultJobIdAndQueryId` (L7333-L7384) | TableResult jobId/queryId/jobCreationReason across modes | own client | PORT |  | |
| IT-172 | `testStatelessQueriesWithLocation` (L7386-L7435) | Stateless query with EU location; wrong location fails | per-test EU dataset; G | PORT |  | |
| IT-173 | `testQueryWithTimeout` (L7437-L7503) | queryWithTimeout returns TableResult or Job (long query) | own client | ADAPT | Swift: enum result; long-running CROSS JOIN query. | |
| IT-174 | `testQueryResultsFormatArrow` (L7505-L7525) | queryArrow | none | DEFERRED | Arrow results format deferred. | |
| IT-175 | `testQueryResultsFormatArrowMultiPage` (L7527-L7550) | queryArrow multi-page | none | DEFERRED | Arrow results format deferred. | |
| IT-176 | `testQueryRowBasedWithArrowFormat` (L7552-L7569) | Row API over Arrow format | none | DEFERRED | Arrow results format deferred. | |
| IT-177 | `testQueryRowBasedWithArrowFormatMultiPage` (L7571-L7600) | Row API over Arrow, multi-page | none | DEFERRED | Arrow results format deferred. | |
| IT-178 | `testQueryResultsFormatArrowFallback` (L7602-L7626) | Arrow fallback path | none | DEFERRED | Arrow results format deferred. | |
| IT-179 | `testQueryRowBasedWithArrowFormatFallback` (L7628-L7648) | Arrow fallback (row API) | none | DEFERRED | Arrow results format deferred. | |
| IT-180 | `testQueryResultsFormatArrowFallbackMultiPage` (L7650-L7673) | Arrow fallback multi-page | none | DEFERRED | Arrow results format deferred. | |
| IT-181 | `testQueryRowBasedWithArrowFormatFallbackMultiPage` (L7675-L7704) | Arrow fallback multi-page (row API) | none | DEFERRED | Arrow results format deferred. | |
| IT-182 | `testUniverseDomainWithInvalidUniverseDomain` (L7706-L7727) | Invalid universe domain -> 401 | fake JSON creds; PUB | ADAPT | Map to Swift auth/universe-domain validation (may fail before RPC). | |
| IT-183 | `testInvalidUniverseDomainWithMismatchCredentials` (L7729-L7749) | Credentials universe mismatch -> error | fake JSON creds | ADAPT | As above. | |
| IT-184 | `testUniverseDomainWithMatchingDomain` (L7751-L7773) | Explicit googleapis.com universe works | PUB; G | PORT |  | |
| IT-185 | `testExternalTableMetadataCachingNotEnable` (L7775-L7814) | External table metadataCacheMode unset -> query works | D, B | PORT |  | |
| IT-186 | `testExternalMetadataCacheModeFailForNonBiglake` (L7816-L7841) | metadataCacheMode on non-BigLake table -> error | D, B | PORT |  | |
| IT-187 | `testObjectTable` (L7843-L7890) | Object table (objectMetadata) over GCS via connection | G; B; connection DEVREL_TEST_CONNECTION (java-docs-samples-testing); US dataset | ADAPT | Gate on BIGQUERY_TEST_CONNECTION_ID; connection SA needs GCS read on the temp bucket. | |
| IT-188 | `testQueryExportStatistics` (L7892-L7914) | EXPORT DATA to GCS -> exportDataStatistics fileCount/rowCount | D, B (write) | PORT |  | |
| IT-189 | `testLoadConfigurationFlexibleColumnName` (L7916-L7970) | Load CSV with autodetect + columnNameCharacterMap V1/V2 (flexible column names) | D, B (load_flexible_column_name.csv) | PORT |  | |
| IT-190 | `testStatementType` (L7972-L7992) | TableResult.statementType for CREATE MATERIALIZED VIEW | D, T | PORT |  | |
| IT-191 | `testOpenTelemetryTracingDatasets` (L7994-L8081) | OTel spans for dataset ops | NEWDS; OTel SDK | DEFERRED | OpenTelemetry tracing: DEFERRED per D4 (#4) unless time permits; Swift would use swift-distributed-tracing. | |
| IT-192 | `testOpenTelemetryTracingTables` (L8083-L8131) | OTel spans for table ops | D; OTel SDK | DEFERRED | OpenTelemetry tracing: DEFERRED per D4 (#4) unless time permits; Swift would use swift-distributed-tracing. | |
| IT-193 | `testOpenTelemetryTracingQuery` (L8133-L8184) | OTel spans for query | D, T; OTel SDK | DEFERRED | OpenTelemetry tracing: DEFERRED per D4 (#4) unless time permits; Swift would use swift-distributed-tracing. | |

### 3.2 `ITHighPrecisionTimestamp` — [it/ITHighPrecisionTimestamp.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/it/ITHighPrecisionTimestamp.java) (8 tests; PORT 8 / ADAPT 0 / N/A 0 / DEFERRED 0)

| ID | Test (lines) | Feature exercised | Resources / fixtures | Class | Notes | Swift test |
|---|---|---|---|---|---|---|
| IT-194 | `query_highPrecisionTimestamp` (L126-L144) | Picosecond TIMESTAMP(12) column read with ISO8601_STRING output format | own DATASET + table (timestampPrecision=12) seeded via insertAll | PORT |  | |
| IT-195 | `insert_highPrecisionTimestamp_ISOValidFormat` (L146-L163) | insertAll ISO strings with 12 fractional digits | same | PORT |  | |
| IT-196 | `insert_highPrecisionTimestamp_invalidFormats` (L165-L204) | insertAll invalid high-precision formats -> row errors | same | PORT |  | |
| IT-197 | `queryNamedParameter_highPrecisionTimestamp` (L206-L232) | Named TIMESTAMP param with picos (CAST) | same | PORT |  | |
| IT-198 | `queryPositionalParameter_highPrecisionTimestamp` (L234-L259) | Positional TIMESTAMP param with picos | same | PORT |  | |
| IT-199 | `queryNamedParameter_highPrecisionTimestamp_microsLong` (L261-L290) | Param from micros long | same | PORT |  | |
| IT-200 | `queryNamedParameter_highPrecisionTimestamp_microsISOString` (L292-L317) | Param from micros ISO string | same | PORT |  | |
| IT-201 | `queryNamedParameter_highPrecisionTimestamp_noExplicitCastInQuery_fails` (L319-L338) | Picos param without CAST -> error | same | PORT |  | |

### 3.3 `ITNightlyBigQueryTest` — [it/ITNightlyBigQueryTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/it/ITNightlyBigQueryTest.java) (7 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 7)

| ID | Test (lines) | Feature exercised | Resources / fixtures | Class | Notes | Swift test |
|---|---|---|---|---|---|---|
| IT-202 | `testInvalidQuery` (L216-L227) | Connection invalid query | nightly dataset/table | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-203 | `testIterateAndOrder` (L232-L294) | Connection large result iteration | nightly 300k-row table | DEFERRED | Connection API (createConnection/executeSelect) deferred. Storage Read API deferred. | |
| IT-204 | `testIterateAndOrderDefaultConnSettings` (L299-L361) | Same with default settings | nightly table | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-205 | `testConnectionClose` (L366-L389) | Connection close | D, TL | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-206 | `testMultipleRuns` (L391-L485) | Connection repeated runs | nightly table | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-207 | `testPositionalParams` (L487-L522) | Connection positional params | nightly table | DEFERRED | Connection API (createConnection/executeSelect) deferred. | |
| IT-208 | `testForTableNotFound` (L524-L569) | Read API on huge public table, table-not-found | bigquery-samples.wikipedia_benchmark.Wiki10B; NEWDS; G | DEFERRED | Connection API (createConnection/executeSelect) deferred. Storage Read API deferred. | |

### 3.4 `ITOpenTelemetryTest` — [it/ITOpenTelemetryTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/it/ITOpenTelemetryTest.java) (5 tests; PORT 0 / ADAPT 0 / N/A 0 / DEFERRED 5)

| ID | Test (lines) | Feature exercised | Resources / fixtures | Class | Notes | Swift test |
|---|---|---|---|---|---|---|
| IT-209 | `testListDatasetsTraced` (L71-L120) | OTel span list datasets | OTel SDK | DEFERRED | OpenTelemetry tracing: DEFERRED per D4 (#4) unless time permits; Swift would use swift-distributed-tracing. | |
| IT-210 | `testGetDatasetNotFoundTraced` (L122-L176) | OTel span 404 | OTel SDK | DEFERRED | OpenTelemetry tracing: DEFERRED per D4 (#4) unless time permits; Swift would use swift-distributed-tracing. | |
| IT-211 | `testClientErrorAndRetriesTraced` (L178-L237) | OTel resend count on retries | OTel SDK | DEFERRED | OpenTelemetry tracing: DEFERRED per D4 (#4) unless time permits; Swift would use swift-distributed-tracing. | |
| IT-212 | `testSimultaneousCallsDoNotAffectResendCountForEachother` (L239-L280) | OTel concurrent resend counts | OTel SDK | DEFERRED | OpenTelemetry tracing: DEFERRED per D4 (#4) unless time permits; Swift would use swift-distributed-tracing. | |
| IT-213 | `testTracingDisabledNoSpansCollected` (L282-L295) | OTel disabled | OTel SDK | DEFERRED | OpenTelemetry tracing: DEFERRED per D4 (#4) unless time permits; Swift would use swift-distributed-tracing. | |

### 3.5 `ITRemoteUDFTest` — [it/ITRemoteUDFTest.java](file:///usr/local/google/home/lawrenceqiu/IdeaProjects/google-cloud-java/java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/it/ITRemoteUDFTest.java) (1 tests; PORT 0 / ADAPT 1 / N/A 0 / DEFERRED 0)

| ID | Test (lines) | Feature exercised | Resources / fixtures | Class | Notes | Swift test |
|---|---|---|---|---|---|---|
| IT-214 | `testRoutineRemoteUDF` (L98-L135) | routines.insert remote function (remoteFunctionOptions endpoint/connection/maxBatchingRows/userDefinedContext) | own ROUTINE dataset; BigQuery Connection created via ConnectionServiceClient (US, CLOUD_RESOURCE) | ADAPT | @Disabled in Java (issue 4103). Swift: gate on BIGQUERY_TEST_CONNECTION_ID (existing connection); no Connection API client needed. | |

## 4. Fixtures and the test project

The Swift ITs run against `GOOGLE_CLOUD_PROJECT=lawrence-test-project-2`. I
checked access from this workstation on 2026-10-08 with `bq` and
`gcloud storage` (read-only checks).

### 4.1 Shared fixtures in `ITBigQueryTest` (abbreviations used in §3)

| Abbrev | Java source | What it is | Satisfiable in lawrence-test-project-2? | Swift plan |
|---|---|---|---|---|
| D | `DATASET`, `ITBigQueryTest.java:L221`, created `L1132-L1134` | Dataset with description and labels `example-label1/2` | Yes | Create in a suite-level fixture. |
| T | `TABLE_ID`, loaded `L1142-L1153` from `gs://BUCKET/load.json` (`JSON_CONTENT` `L634`) with `TABLE_SCHEMA` | All-types table (timestamp, string, int array, bool, bytes, record, numeric, bignumeric, json, interval, range, ...) | Yes | Load the inline JSON with the Swift resumable upload (no GCS needed), or with a load job from the test bucket. |
| TFQ / TRS / TS | `TABLE_ID_FAST_QUERY` `L1155`, `TABLE_ID_FAST_QUERY_BQ_RESULTSET` `L1166`, `TABLE_ID_SIMPLE` `L1179` | Small JSON-loaded tables for fast-query and DML/DDL tests | Yes | Same as T. |
| TL | `TABLE_ID_LARGE` `L1192`, CSV from `src/test/resources/QueryTestData.csv` (12 MB) | Large multi-page table | Yes | Do **not** vendor the 12 MB CSV. Generate rows with `CREATE TABLE ... AS SELECT ... FROM UNNEST(GENERATE_ARRAY(1, N))`. |
| MD / RD | `MODEL_DATASET`, `ROUTINE_DATASET` `L224-L225` | Datasets for BQML models and routines | Yes (BQML enabled) | Suite fixture. Model tests are slow and cost money; tag them `.timeLimit` and allow skipping. |
| UKD / EU | `UK_DATASET` `L222`, `"EU"` datasets in IT-102, IT-156, IT-172 | Cross-location datasets | Yes (EU multi-region) | Create per test and delete in `defer`. |
| B | `BUCKET = RemoteStorageHelper.generateBucketName()` `L619`, objects `L1101-L1131`, deleted `L1216` | Temp GCS bucket with `load.csv`, `load_null.csv`, `load_flexible_column_name.csv`, `load.json`, `load_simple.json`, `load_large.csv`, `load_bq_resultset.json`; also receives extract and EXPORT DATA output and hive `key=foo/data.json` | Yes. The project has buckets, for example `lawrence-test-project-2-test-bucket`, and the caller can create buckets. | **Decided (#17):** a test-only dependency on `swift-google-cloud-storage`, used only by the IntegrationTests target. The ITs create their own bucket `swift-bq-it-<date>-<hex>` and delete it, with its objects, afterwards. |
| CSD | `CLOUD_SAMPLES_DATA` `L236-L237` (env `CLOUD_SAMPLES_DATA_BUCKET`, default `cloud-samples-data`) | `bigquery/hive-partitioning-samples/{autolayout,customlayout}/`, `bigquery/numeric/numeric_38_12.parquet`, `bigquery/federated-formats-reference-file-schema/{a,b,c}-twitter.{avro,parquet}` | Yes. All listed objects are publicly readable (verified). | Use as is, with the same env override. |
| PUB | `PUBLIC_PROJECT`/`PUBLIC_DATASET` `L805-L806`, literals | `bigquery-public-data`: `census_bureau_international`, `samples.shakespeare`, `new_york_taxi_trips.tlc_yellow_trips_2017`, `new_york.311_service_requests`, `usa_names.usa_1910_current`. Nightly test only: `bigquery-samples.wikipedia_benchmark.Wiki10B` | Yes (public; query bytes billed to the project). `samples.shakespeare` verified. | Use as is. Only IT-106 scans much data. |
| G | `globalBigQuery` `L1094-L1099` | Second client pinned to the global endpoint, for public data and cross-region work | Yes | Not needed unless the suite targets a regional endpoint. Use one client. |
| CONN | `projects/java-docs-samples-testing/locations/us/connections/DEVREL_TEST_CONNECTION` (`L2456`, `L7855`) | Cloud-resource connection for BigLake and object tables (IT-034, IT-187) | **No** (foreign project). The project does have `492781389931.us.test-connection-id-ace13f7e` (CLOUD_RESOURCE, SA `bqcx-492781389931-m93p@gcp-sa-bigquery-condel.iam.gserviceaccount.com`). It is probably left over from a Java `ITRemoteUDFTest` run. | **Decided (#17):** gate on env `BIGQUERY_TEST_CONNECTION_ID`; our runs use `us.test-connection-id-ace13f7e`. The connection SA needs `roles/storage.objectViewer` on the temp bucket. Skip when the variable is unset. |
| IAM | IT-005, IT-007, IT-010, IT-021, IT-038, IT-061, IT-062 | Dataset ACL and table IAM edits, including `allUsers` and IAM conditions on the caller's email | Partly. `allUsers` grants may be blocked by an org policy (domain-restricted sharing). | Use the caller's own principal or a group. Treat `403 constraints/iam.allowedPolicyMemberDomains` as a skip. |
| CREDS | `FAKE_JSON_CRED_WITH_GOOGLE_DOMAIN` / `..._INVALID_DOMAIN` `L808`, `L846` | Inline fake service-account JSON for the universe-domain tests | Yes (no live credential) | Port as inline fixtures (ADAPT; depends on `swift-google-auth` universe-domain support). |
| Session CSV | `src/test/resources/sessionTest.csv` (2.7 KB) | Writer load into `_SESSION` (IT-109) | Yes | Small enough to inline or vendor. |
| HPT | `ITHighPrecisionTimestamp.java:L60-L124` | Own dataset and table with a `TIMESTAMP` field `timestampPrecision=12`, seeded by `insertAll`. The client uses `TimestampFormatOptions.ISO8601_STRING`. | Yes, if the feature is enabled for the project. Verify on the first run. | Own suite fixture. |
| Nightly | `ITNightlyBigQueryTest` | Large generated table for Connection/Read API | n/a | DEFERRED with the Connection API. |

### 4.2 Unique names and cleanup (proposal for Swift ITs)

Java uses `gcloud_test_dataset_temp_<uuid>` for datasets
(`RemoteBigQueryHelper.java:L44`, `L71-L74`), `model_<uuid>` and
`routine_<uuid>` for models and routines (`L76-L82`), and
`prefix + UUID.substring(0, 8)` for tables (`ITBigQueryTest.java:L1077-L1079`).
Cleanup is `delete(dataset, deleteContents())` in `@AfterAll`
(`L1207-L1214`). This cleanup does not work reliably: the test project
currently holds **89 leaked `gcloud_test_dataset_temp_*` datasets**.

Proposal, adopted by the coordinator in board #17:

1. **Names.** Use `swift_bq_it_<yyyyMMdd>_<8 random hex>` for datasets,
   with an optional `_<purpose>` suffix (`[A-Za-z0-9_]`, at most 1024
   characters). Tables, models, routines, and jobs use
   `<purpose>_<8 hex>`. GCS objects go under
   `swift-bq-it/<run-id>/<purpose>/...`. Generate one `runID` per test
   process and reuse it, so a failed run can be found and removed as a unit.
2. **Labels.** Label every dataset `swift-bq-it=true` and
   `created=<unix-seconds>`. Label every job and load
   `swift-bq-it-run=<runID>`.
3. **Cleanup.** Each test owns its resources and deletes them in
   `defer { Task { ... } }`, or better, a `withTemporaryDataset { }` helper
   that always deletes with `deleteContents=true`, also on throw. Suite
   fixtures use the same helper at suite scope.
4. **Janitor.** At suite start, delete datasets labelled `swift-bq-it=true`
   that are older than 24 h. This keeps the project clean even when a run
   is killed. The janitor may only touch `swift_bq_it_*` / `swift-bq-it-*`
   resources. Never delete Java's `gcloud_test_dataset_temp_*` datasets or
   anything else the Swift suite did not create (#17).
5. **Gating.** Follow `swift-google-cloud-storage`: use
   `.enabled(if: ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil)`.
   Gate the connection-dependent tests on `BIGQUERY_TEST_CONNECTION_ID`,
   and gate slow BQML/large-scan tests behind
   `GOOGLE_CLOUD_BIGQUERY_SLOW_TESTS=1`.
6. **Eventual consistency.** Template-suffix tables (IT-049), streaming
   buffers, and policy changes can lag. Poll with a bounded timeout instead
   of a fixed sleep.

