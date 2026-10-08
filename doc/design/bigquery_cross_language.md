# BigQuery Client Libraries: Cross-Language Survey

This survey compares the hand-written BigQuery clients in Java (the reference),
Go, Python, Node.js, and Rust. It establishes the feature set and idioms the
Swift port (`GoogleCloudBigQuery`) should have. It complements
`bigquery_reference_behavior.md` (the Java behavioral contract) and feeds
`bigquery.md` (the Swift design).

## Sources and citation prefixes

| Prefix  | Source (snapshot)                                                                                   | Notes                                                                    |
| ------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `J/`    | `google-cloud-java/java-bigquery/google-cloud-bigquery/src/main/java/com/google/cloud/bigquery/`    | Local checkout, the reference.                                           |
| `go:`   | `/tmp/bq-refs/go/bigquery/` (`cloud.google.com/go/bigquery`)                                        | Shallow clone of `googleapis/google-cloud-go`.                           |
| `py:`   | `/tmp/bq-refs/python/google/cloud/bigquery/`                                                        | Shallow clone of `googleapis/python-bigquery`.                           |
| `node:` | `/tmp/bq-refs/node/src/`                                                                            | Shallow clone of `googleapis/nodejs-bigquery`.                           |
| `rs:`   | `google-cloud-rust/src/bigquery/src/`                                                               | A hand-written veneer over the generated `google-cloud-bigquery-v2` crate. |

Line numbers refer to these snapshots (2026-10-08).

> [!NOTE]
> Rust is the closest match to this repo's architecture: a generated v2 client
> wrapped by a veneer. Rust is also a close, line-by-line port of Java.
> Use it to see how the generated layer behaves, not as an example of
> idiomatic result handling (see "Rust pitfalls" below).

---

## 1. Feature matrix

Legend: ✅ supported · ◐ partial/raw passthrough · ❌ not supported · — not applicable.

### 1.1 Resource management

| Capability                          | Java                                     | Go                                                     | Python                                        | Node                                   | Rust                                                     |
| ----------------------------------- | ---------------------------------------- | ------------------------------------------------------ | --------------------------------------------- | -------------------------------------- | -------------------------------------------------------- |
| Dataset CRUD + list                 | ✅ `J/BigQuery.java` `create/getDataset/update/delete/listDatasets` | ✅ `go:dataset.go:L207-L497,L881-L888`                 | ✅ `py:client.py:L459,L649,L865,L1220,L1755`  | ✅ `node:dataset.ts`, `bigquery.ts:L1351,L1886` | ✅ `rs:client.rs:L326-L425`                              |
| Table CRUD + list + partitions      | ✅ `listPartitions`                       | ✅ `go:table.go`, `dataset.go:L621`                     | ✅ `py:client.py:L781,L1178,L1449,L1679,L1990,L4031` | ✅ `node:table.ts`                       | ✅ `rs:client.rs:L429-L555`                              |
| Routine CRUD + list                 | ✅                                        | ✅ `go:routine.go:L71-L147`, `dataset.go:L799`          | ✅ `py:client.py:L726,L1134,L1375,L1602,L1936` | ✅ `node:routine.ts`                     | ✅ `rs:client.rs:L644-L740`                              |
| Model get/update/delete/list        | ✅ (no create; models come from `CREATE MODEL`) | ✅ `go:model.go:L81-L129`, `dataset.go:L709`         | ✅ `py:client.py:L1091,L1311,L1525,L1815`      | ✅ `node:model.ts`                       | ✅ `rs:client.rs:L561-L640`                              |
| Row access policies                 | ❌                                        | ❌                                                      | ❌                                             | ❌                                      | ◐ list/get `rs:client.rs:L747-L780`                      |
| Projects list / service account     | ✅ `listProjects`, `getServiceAccount`   | ◐ service account only                                 | ✅ `py:client.py:L347,L396`                    | ◐                                      | ✅ `rs:client.rs:L850-L875` (custom REST `rs:rest.rs:L5`) |
| Table IAM get/set/test              | ✅ `getIamPolicy/setIamPolicy/testIamPermissions` | ✅ `go:iam.go:L31` (`iam.Handle`)               | ✅ `py:client.py:L930,L987,L1066`              | ✅ `node:table.ts:L2487`                 | ✅ `rs:client.rs:L783-L840` (custom REST)                 |
| Labels on datasets/tables/jobs      | ✅                                        | ✅ `go:query.go:L119`                                   | ✅ `py:job/base.py:L279`                       | ✅ (raw metadata)                        | ✅ `rs:query.rs:L298`                                    |
| CMEK encryption config              | ✅ `EncryptionConfiguration.java`         | ✅ `go:table.go:L685`                                   | ✅ `py:encryption_configuration.py`            | ◐ raw                                  | ✅ `rs:query.rs:L217`                                    |
| Table constraints (PK/FK)           | ✅ `TableConstraints.java`, `PrimaryKey.java`, `ForeignKey.java` | ✅ `go:table.go:L173-L206`                    | ✅ `py:table.py:L3499-L3594`                   | ◐ raw                                  | ◐ generated model only                                    |
| Views / materialized views / snapshots / clones / external tables | ✅ `*TableDefinition.java`                | ✅ `go:table.go`, `external.go`                         | ✅ `py:table.py`, `external_config.py`         | ◐ raw                                  | ✅ `rs:schema.rs` `TableDefinition`                       |
| Etag-guarded updates                | ◐ via options                            | ✅ `Update(ctx, upd, etag)` `go:dataset.go:L487`        | ✅ `if_match` etag                              | ◐                                      | ◐                                                         |
| Partial update (field masks)        | ✅ update sends set fields only            | ✅ `*MetadataToUpdate` structs, nullable via `optional` | ✅ `fields=[...]` argument                     | ◐ raw patch                             | ◐ full resource                                           |

### 1.2 Jobs and queries

| Capability                                       | Java                                                                       | Go                                                                         | Python                                                                         | Node                                                        | Rust                                                              |
| ------------------------------------------------ | -------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------- | ----------------------------------------------------------------- |
| Job types: query, load, extract, copy            | ✅ `*JobConfiguration.java`                                                | ✅ `go:query.go`, `load.go:L208`, `extract.go:L133`, `copy.go:L134`        | ✅ `py:job/{query,load,extract,copy_}.py`                                      | ✅ `node:table.ts:L901,L1175,L1352`                         | ✅ via `create_job(Job)` (generated model) `rs:client.rs:L981`    |
| Get/cancel/delete/list jobs                      | ✅                                                                         | ✅ `go:job.go:L49-L275,L1055`                                              | ✅ `py:client.py:L1867,L2234,L2302,L2379`                                      | ✅ `node:job.ts:L436`, `bigquery.ts:L2007`                  | ✅ `rs:client.rs:L1035-L1111`                                     |
| Query fast path (`jobs.query`)                   | ✅ `J/BigQueryImpl.java:L2747-L2760`                                       | ✅ `go:query.go:L402-L467` (`probeFastPath` `L472-L538`)                  | ✅ `py:_job_helpers.py:L420-L640` (`query_and_wait`)                           | ✅ `node:bigquery.ts:L2200-L2283`                           | ✅ `rs:client.rs:L1166-L1257`                                     |
| Fast-path eligibility rule                       | denylist `QueryRequestInfo.isFastQuerySupported`                           | denylist `go:query.go:L480-L496`                                           | **allowlist** `py:_job_helpers.py:L644-L680`                                   | denylist `node:bigquery.ts:L2310-L2328`                     | denylist `rs:query.rs:L368-L381`                                  |
| Stateless queries (`JOB_CREATION_OPTIONAL`)      | ✅ enum `J/QueryJobConfiguration.java:L104-L114`; default for `queryArrow` `J/BigQueryImpl.java:L2819-L2824` | ✅ per-query + client default `go:query.go:L175-L177,L530-L536`             | ✅ `client.default_job_creation_mode` `py:client.py:L299-L305`, `_job_helpers.py:L534-L535` | ✅ `defaultJobCreationMode` `node:bigquery.ts:L285-L292,L2352` | ✅ `rs:query.rs:L96-L97`                                          |
| `queryId` surfaced when no job is created        | ✅                                                                         | ✅ `RowIterator.QueryID()` `go:iterator.go:L99`                             | ✅ `RowIterator.query_id`                                                      | ◐ in raw response                                           | ✅ `TableResult.query_id` `rs:table_data.rs:L431`                 |
| Explicit job (insert + poll)                     | ✅ `create(JobInfo)` + `Job.waitFor`                                       | ✅ `Query.Run` → `Job.Wait`/`Job.Read` `go:query.go:L372`, `job.go:L282-L357` | ✅ `client.query()` → `QueryJob.result()` `py:job/query.py:L1545`              | ✅ `createQueryJob` + `job.getQueryResults`                 | ✅ `create_job` + `wait_for_job` `rs:client.rs:L1114-L1129`       |
| Named + positional parameters                    | ✅ `QueryParameterValue.java`                                              | ✅ `go:params.go:L105,L153` (named only via `Name`, positional if empty)    | ✅ `py:query.py:L513-L953`                                                     | ✅ `params` object/array + `types` `node:bigquery.ts:L135-L147` | ✅ `rs:query_parameter.rs`, `rs:query.rs:L245-L285`               |
| Array/struct/range parameters                    | ✅                                                                         | ✅                                                                         | ✅ `ArrayQueryParameter`, `StructQueryParameter`, `RangeQueryParameter`          | ✅                                                          | ✅                                                                |
| Dry run                                          | ✅ via `create(JobInfo)`; `query()` rejects                                | ✅ `Run` returns job w/ stats; `Read` rejects `go:query.go:L403-L405`        | ✅ returns job/iterator w/ stats                                               | ◐ returns `[]` rows + response `node:bigquery.ts:L2229-L2232` | ✅ via `create_job`; `query` rejects `rs:client.rs:L1153-L1157`   |
| Sessions (`createSession`, `session_id` property) | ✅ `JobStatistics.SessionInfo` `J/JobStatistics.java:L1556`               | ✅ `go:query.go:L137-L141`, `job.go:L434-L435`                              | ✅ `py:job/base.py:L501,L1150`, `query.py:L35`                                  | ✅ `node:bigquery.ts:L2341,L2358`                           | ✅ `rs:query.rs:L82-L95`                                          |
| DML stats / affected rows                        | ✅ `getDmlStats` `J/JobStatistics.java:L885`                               | ✅ `go:job.go:L515-L517`                                                   | ✅ `py:job/query.py:L1386`                                                     | ◐ raw                                                       | ◐ `num_dml_affected_rows` only `rs:table_data.rs:L437`            |
| Scripts / child jobs                             | ✅ `ScriptStatistics` `L1082`, `JobListOption.parentJobId`                 | ✅ `Job.Children` `go:job.go:L141`, `ScriptStatistics` `L782`              | ✅ `list_jobs(parent_job=)` `py:client.py:L2382`, `py:job/base.py:L1118`        | ◐ `getJobs({parentJobId})`                                  | ◐ generated `list_jobs` builder                                   |
| Transactions info                                | ✅ `TransactionInfo` `L1484`                                               | ◐                                                                          | ✅                                                                             | ◐                                                           | ◐                                                                 |
| Job timeout (`jobTimeoutMs`)                     | ✅                                                                         | ✅ `go:query.go:L151` (disables fast path)                                  | ✅ (allowed on fast path)                                                      | ✅ (disables fast path)                                      | ✅ `rs:query.rs:L89`                                              |
| Client-side wait timeout                         | ✅ `queryWithTimeout` returns `TableResult` **or** `Job` (`Object`)          | `context` deadline                                                        | ✅ `wait_timeout` + cancel `py:_job_helpers.py:L682-L740`                       | ✅ `timeoutMs` → error `node:job.ts:L605-L616`               | ❌                                                                |

### 1.3 Data plane

| Capability                                   | Java                                                          | Go                                                                                       | Python                                                                 | Node                                                                    | Rust                                                                |
| -------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Lazy, paginated row iteration                | ✅ `TableResult.iterateAll()` (page-based)                    | ✅ `RowIterator.Next(dst)` `go:iterator.go:L47-L189`                                     | ✅ `RowIterator` (api_core page iterator)                              | ✅ `createQueryStream`, `getRows` auto-paginate `node:bigquery.ts:L379` | ❌ `query()` buffers **all** pages into `Vec<Row>` `rs:client.rs:L1211-L1232,L1352-L1369` |
| Untyped row access                           | `FieldValueList` by index/name, `FieldValue.get*Value()` `J/FieldValue.java:L113-L324` | `[]Value`, `map[string]Value` `go:value.go:L35-L54`                    | `Row` index/key/attr `py:table.py:L1613`                               | plain JS objects `node:bigquery.ts:L592`                                | `Row`/`FieldValue` + `get::<T>` `rs:row.rs:L237-L246`               |
| Decode rows into user types                  | ❌                                                            | ✅ struct + `bigquery:"name"` tags, `ValueLoader` `go:value.go:L37-L39`, `iterator.go:L148-L160` | ◐ `to_dataframe`/`to_arrow` (pandas/pyarrow)                           | ❌                                                                      | ◐ per-column `FromValue` `rs:value.rs:L995-L1110` (no struct derive) |
| Schema inference from user types             | ❌                                                            | ✅ `InferSchema` `go:schema.go:L374-L426`                                                 | ◐ from DataFrame                                                       | ❌                                                                      | ❌                                                                  |
| NULL handling for typed reads                | `FieldValue.isNull()`                                         | `NullInt64`… wrappers `go:nulls.go:L40-L117`; NULL arrays → empty `go:iterator.go:L148`   | `None`                                                                 | `null`                                                                  | `Option<T>` `rs:value.rs:L1101`                                    |
| `insertAll` streaming                        | ✅ `insertAll(InsertAllRequest)`                              | ✅ `Inserter.Put` (structs, `ValueSaver`, `StructSaver`) `go:inserter.go:L95`, `value.go:L538,L631` | ✅ `insert_rows`, `insert_rows_json` `py:client.py:L3745,L3881`         | ✅ `table.insert` `node:table.ts:L2083`                                 | ✅ `insert_all` `rs:client.rs:L879`                                 |
| insertId default                             | none (caller supplies)                                         | **random ID per row**; opt-out `NoDedupeID` `go:inserter.go:L27-L30,L210-L215`            | **UUID per row** (`AutoRowIDs.GENERATE_UUID`) `py:client.py:L3886-L3978` | **UUID per row** (`createInsertId=true`) `node:table.ts:L81,L1962`        | none `rs:table_data.rs:L39-L60`                                     |
| Per-row insert errors                        | `InsertAllResponse.getInsertErrors()`                          | `PutMultiError`/`RowInsertionError` `go:error.go:L62-L98`                                | list of error mappings returned                                        | `PartialFailureError` + `partialRetries=3` `node:table.ts:L82,L2051`     | `InsertAllResponse` `rs:table_data.rs`                              |
| Load from local data                         | ✅ `writer()` → `TableDataWriteChannel` (resumable)            | ✅ `ReaderSource` media upload `go:file.go:L29`, `load.go:L228`                            | ✅ `load_table_from_file/json/dataframe` `py:client.py:L2577-L2939`    | ✅ `createLoadJob(path)`, `createWriteStream` `node:table.ts:L1352,L1653` | ✅ `TableDataWriteChannel`, 256 KiB-multiple chunks `rs:write_channel.rs:L35-L39,L378` |
| Load from GCS URIs                           | ✅                                                            | ✅ `GCSReference` `go:gcs.go:L25`                                                        | ✅ `load_table_from_uri` `py:client.py:L2493`                          | ✅                                                                      | ✅ (generated job model)                                            |
| Extract / copy                               | ✅                                                            | ✅                                                                                       | ✅ `py:client.py:L3252,L3362`                                          | ✅                                                                      | ✅ (generated job model)                                            |
| Storage Read API acceleration                | ✅ `Connection`/`ConnectionSettings.useReadAPI` `J/ConnectionSettings.java:L36`; `queryArrow` | ✅ `EnableStorageReadClient` `go:bigquery.go:L122-L139`; `IsAccelerated`, `ArrowIterator` `go:storage_iterator.go:L370-L378` | ✅ `bqstorage_client` for `to_arrow/to_dataframe` `py:table.py:L1966-L2242` | ❌ (separate package)                                                    | ❌                                                                  |
| Arrow output                                 | ✅ `ArrowQueryResult`                                          | ✅ `go:arrow.go`                                                                         | ✅ `to_arrow`                                                          | ❌                                                                      | ❌                                                                  |
| DB-API / notebooks                           | JDBC driver is separate                                       | ❌                                                                                       | ✅ `py:dbapi/`, `py:magics/`                                            | ❌                                                                      | ❌                                                                  |

### 1.4 Types

| Type                                   | Java                                          | Go                                         | Python                                       | Node                                                   | Rust                                                     |
| -------------------------------------- | --------------------------------------------- | ------------------------------------------ | -------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------- |
| INT64                                  | `long`                                        | `int64`                                    | `int`                                        | `number`; throws past 2^53 unless `wrapIntegers` → `BigQueryInt` `node:bigquery.ts:L294,L987,L1030` | `i64`                                                     |
| NUMERIC / BIGNUMERIC                   | `BigDecimal`                                  | `*big.Rat` `go:value.go:L873-L879`         | `decimal.Decimal`                            | string / `Big`                                         | `rust_decimal::Decimal` (BIGNUMERIC overflow risk)        |
| TIMESTAMP                              | micros; `getTimestampInstant` `J/FieldValue.java:L220-L244` | `time.Time`                         | `datetime` (UTC); picosecond opt-in          | `BigQueryTimestamp` `node:bigquery.ts:L2759`           | `DateTime<Utc>`; HALF_UP micro rounding                   |
| DATE / TIME / DATETIME                 | strings                                       | `civil.Date/Time/DateTime`                 | `date`/`time`/`datetime` (naive)             | `BigQueryDate`/`BigQueryTime`/`BigQueryDatetime`       | `NaiveDate`/`NaiveTime`/`NaiveDateTime`                  |
| JSON                                   | string `J/StandardSQLTypeName.java:L60-L61`   | string (`JSONFieldType`) `go:schema.go:L330`| parsed object                                | string; `parseJSON` opt-in `node:bigquery.ts:L2583-L2584` | string                                                    |
| INTERVAL                               | `PeriodDuration` `J/FieldValue.java:L305`     | `IntervalValue` `go:intervalvalue.go`      | `relativedelta` `py:_helpers.py:L184-L216`   | string                                                 | `IntervalValue` `rs:value.rs:L178`                        |
| RANGE<T>                               | `Range` `J/FieldValue.java:L272`              | `RangeValue` `go:rangevalue.go:L20`        | `RangeQueryParameter`; dict on read          | `BigQueryRange` `node:bigquery.ts:L2608`               | `Range` `rs:value.rs:L58`                                 |
| GEOGRAPHY                              | string (WKT)                                  | string                                     | string (WKT; shapely for DataFrames)          | `Geography` `node:bigquery.ts:L2744`                    | string                                                    |

### 1.5 Cross-cutting

| Capability                 | Java                                                                                         | Go                                                                                                 | Python                                                                                                 | Node                                                                          | Rust                                                                                       |
| -------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Default per-RPC retries    | HTTP 500/502/503/504 `J/BigQueryException.java:L39-L41`, plus rate-limit message/regex `J/BigQueryImpl.java:L651-L655`, `J/BigQueryErrorMessages.java:L20-L25` | reasons `backendError`, `rateLimitExceeded`; 500/502/503/504; network errors; backoff 1s→32s ×2 `go:bigquery.go:L234-L325` | reasons `rateLimitExceeded`, `backendError`, `internalError`, `badGateway`; 429/500/502/503; conn errors; 10-minute deadline `py:retry.py:L25-L41,L81` | `@google-cloud/common`: 429/5xx + rate-limit reasons, `maxRetries=3` `node:bigquery.ts:L228-L262` | gax retry/backoff policies + per-RPC idempotency flags `rs:client.rs:L119-L139`, `rs:rest.rs:L81-L251` |
| Job-level retry            | rate-limit messages while waiting `J/Job.java:L83-L86`                                         | `jobs.insert` / `jobs.query` add `jobRateLimitExceeded`, `internalError` `go:bigquery.go:L185,L213,L259` | **re-runs the query with a new job ID** on `jobBackendError`/`jobInternalError`/`jobRateLimitExceeded` (40-minute deadline) `py:retry.py:L61,L129-L170` | 409 on retried `jobs.insert` is treated as success `node:bigquery.ts:L1773-L1790` | ❌                                                                                          |
| Error model                | `BigQueryException` (code, reason, `List<BigQueryError>`), `JobException`                      | `*googleapi.Error`; `bigquery.Error{Location,Message,Reason}`, `MultiError`, `PutMultiError` `go:error.go:L26-L98`; `JobStatus.Err()` | `google.api_core.exceptions.*` with `.errors`; `QueryJob.result()` raises                             | `ApiError` (`errors[]`), `PartialFailureError`                                 | `gax::Error` carrying `JobError{job_id, errors}` details `rs:error.rs:L151-L198`; `RowError`/`ValueError` |
| Endpoint / emulator        | `setHost`; IT helper `J/testing/RemoteBigQueryHelper.java`                                    | `option.WithEndpoint`; HTTP replay for ITs (`bigquery.replay`)                                     | `BIGQUERY_EMULATOR_HOST` `py:_helpers.py:L61,L131`                                                     | `BIGQUERY_EMULATOR_HOST` `node:bigquery.ts:L402`                               | `endpoint` option; `httptest` mock server in unit tests `rs:client.rs:L119-L121`           |
| Tracing                    | OpenTelemetry `J/telemetry/`                                                                 | OpenCensus/OTel `go:trace.go`                                                                      | OpenTelemetry `py:opentelemetry_tracing.py`                                                            | ❌                                                                            | ❌                                                                                          |

---

## 2. Idiom notes

### 2.1 How each language models results

| Language | Shape                                                                                                                                                                         | Observations                                                                                                     |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Java     | `TableResult` (pages) → `FieldValueList` → string-backed `FieldValue` with `getLongValue()` and similar getters.                                                              | Values are typed only when read. Accessing a column by name requires the schema. Verbose, but it never loses precision. |
| Go       | `RowIterator.Next(dst)`. `dst` can be `*[]Value`, `*map[string]Value`, a struct pointer (reflection plus `bigquery:"col,nullable"` tags), or a custom `ValueLoader`. `iterator.Done` is the sentinel. | The most ergonomic typed decoding: one struct type per iterator, and `Null*` wrappers for nullable columns. Schema inference from the same struct is reused by `Inserter`. |
| Python   | `RowIterator` of `Row`. `Row` supports index, key, and attribute access, `.get()`, `.items()` `py:table.py:L1613-L1660`. Bulk paths go to pandas or pyarrow.                   | Values are converted to native types eagerly, using the schema.                                                  |
| Node     | Arrays of plain objects keyed by column name, converted by `mergeSchemaWithRows_` `node:bigquery.ts:L592`. Wrapper classes cover lossy types (`BigQueryInt`, `BigQueryTimestamp`, ...). | Simple, but INT64 precision and JSON parsing are opt-in footguns.                                                 |
| Rust     | `TableResult { rows: Vec<Row>, total_rows, schema, job_id, ... }` `rs:table_data.rs:L419-L437`. `Row` → `FieldValue`. `row.get::<T>(i)` via `FromValue`.                       | A faithful Java port. It buffers everything and has no struct derive.                                            |

**Swift mapping (recommended):**

- Model `RowSequence: AsyncSequence` (element `Row`) pages lazily through
  `jobs.query` → `jobs.getQueryResults` → `tabledata.list`. It exposes
  `schema`, `totalRows`, `jobID?`, `queryID?`, and statistics on a wrapping
  `QueryResult`.
- Make `Row` a `Sendable` value type with `subscript(Int)` and
  `subscript(String)` that return a `FieldValue` enum (`.null`, `.int64`,
  `.float64`, `.numeric`, `.string`, `.bytes`, `.timestamp`, `.date`, `.time`,
  `.datetime`, `.json`, `.interval`, `.range`, `.array`, `.struct`, ...).
  Convert values eagerly using the schema, as Python does. Keep a
  Java-style lossless raw string available where precision matters.
- Use **`Decodable` rows** as Swift's equivalent of Go's struct tags. A
  custom `Decoder` over `Row` maps `CodingKeys` to column names, nested
  `Decodable` to STRUCT, arrays to REPEATED, and `Optional` to NULL. Expose it
  as `row.decode(T.self)` and `result.rows(as: T.self) -> some AsyncSequence<T>`.
  For inserts, `Encodable` → insertAll JSON is the mirror (Go `StructSaver`).
- Skip Go-style schema inference from types for now. Swift `Codable` has
  no runtime type metadata comparable to Go reflection. Defer it.

### 2.2 Query configuration

| Language | Style                                                                                                    |
| -------- | -------------------------------------------------------------------------------------------------------- |
| Java     | Immutable `QueryJobConfiguration` built with a builder; `JobOption`/`QueryResultsOption` varargs.          |
| Go       | Mutable option struct `QueryConfig` embedded in a `Query` handle (`client.Query(sql)`); zero values mean "unset". |
| Python   | `QueryJobConfig` property bag plus keyword arguments on `client.query(...)`/`query_and_wait(...)`.         |
| Node     | Plain object literal (`Query`), merged with the REST resource.                                            |
| Rust     | Struct with public fields plus chained `set_*` methods `rs:query.rs:L107-L350`.                          |

**Swift:** use a `struct QueryConfiguration: Sendable` with `var` properties,
optionals for "unset", and `init(_ sql: String, parameters: ...)`. Never use a
builder. Go's zero-value-means-unset approach does not translate well because
`Bool` cannot distinguish unset from false (for example `useQueryCache`), so
use `Bool?`. Type per-call options (page size, timeout) as small structs or
default arguments, not varargs `Option` objects.

### 2.3 Query parameters

- **Inferred from native values:** Go (`QueryParameter{Name, Value any}`,
  reflection), Node (`params` plus an optional `types` override), and Rust
  (`ToQueryParameter` trait `rs:query_parameter.rs:L790`).
- **Explicitly typed:** Python (`ScalarQueryParameter("x", "INT64", 1)`) and
  Java (`QueryParameterValue.int64(1)`).
- **Swift:** a `QueryParameterValue` enum is the source of truth, with a
  `QueryParameterConvertible` protocol on `Int`, `Int64`, `Double`, `Bool`,
  `String`, `Data`, `Date` (→ TIMESTAMP), `Decimal` (→ NUMERIC), arrays,
  and `Optional`. Support literal-friendly calls such as
  `parameters: ["min": 10, "name": "x"]` and `positional: [1, "a"]`. Require the
  explicit enum for ambiguous types: DATE vs DATETIME vs TIMESTAMP, JSON,
  GEOGRAPHY, BIGNUMERIC, RANGE, STRUCT, and typed empty arrays.

### 2.4 Job waiting

| Language | API                                                                     | Polling                                                                                                                                                                             |
| -------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Java     | `Job.waitFor(RetryOption...)`, `Job.getQueryResults()`                  | Non-query jobs: 1s→1min ×2, jittered, 12h total. Query jobs: constant 3s, 12h, using `getQueryResults(maxResults=0)` `J/Job.java:L59-L79`.                                            |
| Go       | `Job.Wait(ctx)` returns `(*JobStatus, error)`                           | Query jobs: `getQueryResults(maxResults=0)` with 50ms ×1.3 up to 60s `go:job.go:L359-L380`. Others: gax default backoff `L299`. **Footgun:** `Wait` returns `err == nil` for a failed job, so the caller must check `status.Err()` `go:job.go:L277-L281`. |
| Python   | `QueryJob.result(timeout=, retry=, job_retry=)` (an api_core `PollingFuture`) | Server long-poll through `getQueryResults`; per-call timeout 128s `py:retry.py:L204`.                                                                                                |
| Node     | `job.promise()` / `'complete'` event emitter; `job.getQueryResults()`   | `poll_` via the common `Operation` `node:job.ts:L656`.                                                                                                                              |
| Rust     | `wait_for_job(&JobId)`                                                  | **Fixed 50ms sleep, no backoff, no deadline** `rs:client.rs:L1114-L1129,L1325`.                                                                                                      |

**Swift:** `func wait(for job: JobID, ...) async throws -> Job` **throws** on
`status.errorResult` (avoid Go's footgun). Use exponential backoff with a cap,
and rely on the server long-poll (`getQueryResults timeoutMs`) for queries.
Honor `Task` cancellation between polls. Inject a `Clock` so unit tests
don't sleep.

### 2.5 Errors

**Swift:** one public `BigQueryError` type. It wraps the gax/HTTP status and
keeps the **full** `[ErrorProto]` list (`reason`, `location`, `message`,
`debugInfo`) plus an optional `jobID`. Provide cases or flags for
service errors, job failures, insertAll partial failures (row index →
errors), and client-side decoding errors.

Keep public methods on plain `throws` and document the concrete type.
Typed throws (`throws(BigQueryError)`) would force every lower-layer error
(auth, transport, cancellation) to be wrapped, and it locks the contract.
Restrict typed throws to pure, closed-domain helpers such as value parsing.
`CancellationError` should propagate unchanged.

### 2.6 What translates well vs. what does not

| Translates well to Swift                                                              | Does not translate                                                                         |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Go/Python/Node lazy pagination → `AsyncSequence`                                      | Go reflection-driven struct tags (use `Decodable`/`Encodable`)                              |
| Go `ValueLoader`/`ValueSaver` → `Decodable`/`Encodable` rows                          | Java builders, `toBuilder`, `Serializable`, `Option...` varargs                             |
| Go/Python per-row auto insertIds → a simple `InsertRow(id:, value:)` value type       | Java `Info` vs handle class hierarchy (`Dataset extends DatasetInfo` holding the client); use plain values plus client methods (Python/Rust style) |
| Python `query_and_wait` semantics → `client.query(...) async throws -> QueryResult`   | Java `queryWithTimeout` returning `Object` (TableResult or Job); use an enum or separate methods |
| Python allowlist fast-path rule → typed mapping from `QueryConfiguration` to `QueryRequest` | Node callbacks, event-emitter polling, and stream piping                                    |
| Rust's idempotency-aware retry flags (`insertAll` only if every row has an ID; `setIamPolicy` only with an etag) | Python pandas/pyarrow/DB-API/IPython magics                                                 |
| Swift `Optional` for NULL; `Decimal` for NUMERIC                                      | Node `wrapIntegers`/`parseJSON` knobs (Swift has native `Int64`; return JSON as a typed value) |
| `Sendable` value-type configs and resources                                           | Rust's buffer-all `TableResult.rows: Vec<Row>`                                              |

---

## 3. Behavioral differences that matter

| #  | Topic                                    | What differs                                                                                                                                                                                                                                                                                                                                             | Swift recommendation                                                                                                                                         |
| -- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1  | `useLegacySql` default                   | The **server** defaults to legacy SQL for `jobs.insert` and for views. Every client defaults to GoogleSQL and sends `false` explicitly: Java `J/QueryJobConfiguration.java:L136`, `J/ViewDefinition.java:L137`; Go `go:query.go:L228-L232`; Python `py:_job_helpers.py:L288,L330`, views `py:table.py:L897-L900`; Node `node:bigquery.ts:L1513,L2350`; Rust `rs:query.rs:L111`. When reading config back, Go treats an absent value as legacy=true `go:query.go:L275`. | Default `false` and **always send it explicitly**, including on view definitions. When decoding server resources, treat an absent value as `true`.               |
| 2  | Fast-path eligibility                    | Java/Go/Node/Rust use a denylist. Python uses an allowlist, because the backend silently ignores unknown `QueryRequest` fields `py:_job_helpers.py:L648-L651`. The lists also disagree: Go blocks `JobTimeout` and `Continuous`, Python allows `jobTimeoutMs`, `reservation`, `maxSlots`, and Rust allows `job_timeout_ms`. All languages force the slow path when the caller supplies a job ID. | Build the `QueryRequest` from typed fields. Take the fast path only if every set field has a `QueryRequest` counterpart (allowlist). Unit-test each field.        |
| 3  | Job creation mode default                | Java: unspecified (= REQUIRED), except `queryArrow`, which forces OPTIONAL `J/BigQueryImpl.java:L2819-L2824`. Go/Python/Node: a client-level default, unset unless configured.                                                                                                                                                                         | Add a client option `defaultJobCreationMode` with a per-query override; default unset. Results must work when `jobReference` is absent (use `queryId`).         |
| 4  | Paging when no job exists                | With OPTIONAL, `jobs.query` may return rows with no job. If there are more pages, the server creates a job, and clients page with `getQueryResults` on that job (Go `go:query.go:L436-L454`; Python `py:_job_helpers.py:L577`).                                                                                                                        | `RowSequence` holds either "inline rows only" or "job + page token". Do not assume a `jobID`.                                                                  |
| 5  | Per-RPC retry predicates                 | Section 1.5: Java retries mostly on HTTP 5xx plus rate-limit **message** matching. Go/Python match on `errors[0].reason`. Python also retries 429. Go/Python retry transport errors.                                                                                                                                                                    | Retry 429/500/502/503/504 and reasons `rateLimitExceeded`, `backendError`, `internalError`, `badGateway`, idempotent RPCs only. Use gax backoff (Go: 1s→32s ×2). |
| 6  | `jobs.insert` retries                    | Go retries only when it set a client-generated job ID `go:bigquery.go:L180-L188`. Node treats 409 after a retry as success `node:bigquery.ts:L1773-L1790`. Python retries the *whole query* with a new job ID on job-level failures, and forbids this with a user-supplied job ID `py:_job_helpers.py:L225`.                                            | Always generate the job ID client-side (UUID) so `jobs.insert` is idempotent and retryable. Treat 409 for our own generated ID as "fetch and continue". **Defer** Python-style whole-query re-run. |
| 7  | `jobs.query` requestId                   | Go/Python set a fresh `requestId` per call for idempotent retries `go:query.go:L504`, `py:_job_helpers.py:L539-L541`.                                                                                                                                                                                                                                  | Always set `requestId` (UUID) and mark `jobs.query` idempotent.                                                                                                |
| 8  | Client-side query timeout                | Python cancels the job on `wait_timeout` `py:_job_helpers.py:L694-L738`. Node returns an error without cancelling `node:job.ts:L605-L616`. Java `queryWithTimeout` returns the unfinished `Job`. Go relies on the context. Rust has no timeout.                                                                                                          | **Decided (#8):** cancelling the Swift `Task` only stops waiting or paging. It never sends `jobs.cancel`; server-side cancel stays an explicit `cancelJob`, as in Java `waitFor`. |
| 9  | Missing `totalRows`                      | Go sets `TotalRows` only after the first page fetch `go:iterator.go:L75,L210`. Python `total_rows` may be `None`. Rust maps absent to `0` and then **skips `tabledata.list`** `rs:client.rs:L1195,L1331-L1341`. For DDL and scripts the field can be absent.                                                                                              | `totalRows: UInt64?`. Never infer "no rows" from an absent count; page until there is no `pageToken`.                                                          |
| 10 | Timestamp wire format                    | Go/Python/Node request `formatOptions.useInt64Timestamp=true` (lossless micros) `go:iterator.go:L29`, `node:bigquery.ts:L2346`, `py:_job_helpers.py:L296-L298`. Java defaults to `false` (float-seconds strings, HALF_UP rounding) `J/DataFormatOptions.java:L51`, and Rust copies Java. Python offers picosecond output via `ISO8601_STRING`.             | Always request int64 micros. Defer picosecond output.                                                                                                         |
| 11 | insertId defaults                        | Go/Python/Node auto-generate per-row IDs, with an opt-out. Java/Rust send none, and Rust retries `insertAll` only if every row has an ID `rs:rest.rs:L92-L113`.                                                                                                                                                                                        | **Decided (#8):** auto-generate a UUID for any row without an ID (Go/Python/Node), so `insertAll` is retry-safe. Callers can supply IDs or opt out, and opting out disables retries. This is an intentional difference from Java. |
| 12 | Dry run                                  | Java/Go/Rust reject dry run in the query/read path. Node returns empty rows. Python returns a job with statistics.                                                                                                                                                                                                                                        | Add a dedicated `dryRun(_:) async throws -> QueryStatistics`; `query()` rejects `dryRun`.                                                                       |
| 13 | Job failure surfacing                    | Go `Wait` returns success for a failed job. Java throws `JobException`. Python raises from `result()`. Rust returns `JobError`.                                                                                                                                                                                                                          | Waiting and query APIs **throw** on `errorResult`. The error carries all `errors[]` plus the `jobID`.                                                          |
| 14 | NUMERIC/BIGNUMERIC precision             | Java `BigDecimal` and Go `big.Rat` are exact. Rust `Decimal` (28 digits) cannot hold BIGNUMERIC. Node uses strings.                                                                                                                                                                                                                                     | Foundation `Decimal` (38 digits) fits NUMERIC(38,9) but **not** BIGNUMERIC (76.76). Use a string-backed `BigNumeric` value type, with `Decimal` conversion when it fits. |
| 15 | INT64 precision                          | Node loses precision unless `wrapIntegers` is set.                                                                                                                                                                                                                                                                                                     | Parse into `Int64` directly; no knob needed.                                                                                                                    |
| 16 | NULL arrays                              | BigQuery returns NULL repeated fields as empty arrays, and Go documents this `go:iterator.go:L148-L150`.                                                                                                                                                                                                                                               | Decode REPEATED NULL as `[]`.                                                                                                                                   |
| 17 | Location propagation                     | All clients carry the location on the job reference and pass it to `get`, `getQueryResults`, and `cancel`.                                                                                                                                                                                                                                             | `JobID` includes an optional `location`. The client default location fills it when absent.                                                                     |
| 18 | Result buffering                         | Java/Go/Python/Node page lazily. Rust materializes the full result in memory.                                                                                                                                                                                                                                                                          | Make `AsyncSequence` the default. Convenience `collect()` is OK.                                                                                               |
| 19 | Emulator                                 | Python/Node honor `BIGQUERY_EMULATOR_HOST` (for example the community `goccy/bigquery-emulator`). Java/Go/Rust only offer an endpoint override.                                                                                                                                                                                                         | Add an endpoint override in client options (P0). `BIGQUERY_EMULATOR_HOST` with anonymous credentials is P1.                                                    |

### Rust pitfalls (do not copy)

- `query()` collects every page into memory (`rs:client.rs:L1211-L1232`).
- Fixed 50ms polling with no backoff or deadline (`rs:client.rs:L1127,L1325`).
- A missing `totalRows` becomes `0` and short-circuits row reads (`rs:client.rs:L1195,L1335`).
- Stringly-typed enums in config (`set_priority(impl Into<String>)`, `set_write_disposition(String)`) `rs:query.rs:L147-L159`. Swift should use enums with an `unknown(String)` fallback.

Worth copying from Rust:

- Custom REST calls for endpoints the generated v2 surface lacks:
  `tabledata.list`, `tabledata.insertAll`, table IAM, `projects.list`, and
  resumable upload (`rs:rest.rs:L1-L11`).
- Per-RPC idempotency flags.

> [!IMPORTANT]
> The generated Swift module `generated/swift-google-cloud-bigquery-v2` has the
> same gap. It exposes only `Dataset`, `Job`, `Model`, `Project`, `Routine`,
> `RowAccessPolicy`, and `Table` services, so `tabledata.*`, table IAM,
> `projects.list`, and upload need a hand-written REST path. There is also no
> generated BigQuery Storage v1 module, which supports deferring Storage Read.

---

## 4. Recommended Swift feature scope

**P0** = first release (parity with Java's `BigQuery` interface). **P1** = should land if time permits. **DEFER** = out of scope for now.

| Area                    | Feature                                                                                                                         | Priority | Rationale                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------- |
| Client                  | `BigQueryClient` (project, location, endpoint override, retry/backoff options); a protocol for test doubles (like `StorageProtocol`) | P0       | D1/D3; matches `swift-google-cloud-storage`.                                                     |
| IDs                     | `DatasetID`, `TableID`, `JobID` (with location), `ModelID`, `RoutineID`; parse `project.dataset.table`                           | P0       | Every language has typed IDs.                                                                    |
| Resources               | Dataset/Table/Routine/Model CRUD + list (`AsyncSequence`), table partitions, etag-guarded update, delete with contents           | P0       | Java parity.                                                                                     |
| Table definitions       | Standard, view, materialized view, external, snapshot, clone; partitioning, clustering, CMEK, constraints, labels                 | P0       | Java parity; all are plain value types over the generated model.                                 |
| Jobs                    | Query/load/extract/copy configs as structs; create/get/cancel/delete/list (parent job filter); `wait(for:)` with backoff + throw | P0       | Java parity; fixes Go's footgun.                                                                 |
| Query                   | `query(_:)` → `QueryResult` with `RowSequence`; fast path with allowlist rule; slow path fallback; requestId; job creation mode    | P0       | Highest-traffic API in every language.                                                           |
| Parameters              | `QueryParameterValue` enum (scalar, array, struct, range) + `QueryParameterConvertible`; named and positional                    | P0       | Java parity plus Go/Node ergonomics.                                                             |
| Rows                    | `Row`/`FieldValue` with schema-aware eager conversion; `Decodable` row decoding                                                  | P0       | D3; Go's best idea, done with Codable.                                                           |
| Statistics              | Query stats: bytes processed, cache hit, DML stats, session info, script statistics, transaction info                            | P0       | Cheap mappings from the generated model.                                                         |
| Sessions                | `createSession`, `connectionProperties`                                                                                         | P0       | Supported by every language.                                                                     |
| Dry run                 | `dryRun(_:)` returning statistics + schema                                                                                       | P0       | Common need; avoid Node/Python's ambiguous shapes.                                               |
| insertAll               | `insertAll(_:into:)` with `[InsertRow]`, `Encodable` rows, auto-generated UUID insertIds (opt-out), `skipInvalidRows`, `ignoreUnknownValues`, `templateSuffix`; per-row errors | P0       | Java parity plus Go/Python/Node insertId defaults (#8); `Encodable` mirrors Go `StructSaver`.     |
| Table data              | `listRows(table:schema:selectedFields:startIndex:)` as an `AsyncSequence`                                                        | P0       | Java `listTableData`.                                                                            |
| Load                    | Resumable upload from `Data`, a file `URL`, or an `AsyncSequence` of bytes (reuse storage's source abstractions if practical); GCS URIs | P0       | D3/D4 (Java `writer`).                                                                           |
| IAM                     | Table `getIamPolicy`/`setIamPolicy`/`testIamPermissions`                                                                         | P0       | Java parity.                                                                                     |
| Types                   | INT64, FLOAT64, BOOL, STRING, BYTES, NUMERIC (`Decimal`), BIGNUMERIC (string-backed), TIMESTAMP (`Date` + micros), DATE/TIME/DATETIME value types, JSON, GEOGRAPHY (WKT string), INTERVAL, RANGE | P0       | Covered by every language. Lossless types avoid Node/Rust precision bugs.                       |
| Errors                  | `BigQueryError` with all `errors[]`, `jobID`, and insertAll row errors                                                           | P0       | D3.                                                                                              |
| Retries                 | Reason + status predicate (section 3, #5); client-generated job IDs; idempotency-aware                                         | P0       | Combines the Go/Python predicates with Rust's idempotency rules.                                 |
| Projects                | `listProjects`, `serviceAccount`                                                                                                | P1       | Rarely used; needs custom REST.                                                                  |
| Row access policies     | list/get                                                                                                                        | P1       | Not in Java; generated client already has it.                                                    |
| Emulator                | `BIGQUERY_EMULATOR_HOST` + anonymous credentials                                                                                 | P1       | Python/Node have it; enables credential-free tests.                                             |
| Client wait timeout     | Optional `timeout` on `query` that stops waiting (never cancels the job, #8)                                                    | P1       | Python has it; Swift `Task` cancellation already covers most needs.                             |
| Encodable schema        | `Schema(inferredFrom:)`                                                                                                         | DEFER    | Needs reflection Swift lacks; only Go has it.                                                    |
| Whole-query job retry   | Python-style re-run on `jobBackendError`/`jobInternalError`/`jobRateLimitExceeded`                                              | DEFER    | Complex; Java lacks it; revisit after P0.                                                        |
| Storage Read API        | Accelerated reads (Java `Connection`/`useReadAPI`, Go `EnableStorageReadClient`, Python `bqstorage_client`)                     | DEFER    | D4. No generated Storage v1 module yet; gRPC + Arrow/Avro decoding is a large separate slice.   |
| Arrow output            | `queryArrow`, Arrow iterators                                                                                                   | DEFER    | No Swift Arrow dependency in the repo.                                                           |
| Java `Connection` API   | Beta JDBC-like `executeSelect`                                                                                                  | DEFER    | D4; Java-only.                                                                                   |
| Picosecond timestamps   | `ISO8601_STRING` output format                                                                                                  | DEFER    | Python-only; new service feature.                                                                |
| Tracing                 | OpenTelemetry spans                                                                                                             | DEFER    | D4; no tracing convention in sibling Swift packages yet.                                         |
| DataFrame / DB-API / notebooks | —                                                                                                                         | N/A      | Python ecosystem specific.                                                                       |

### Decisions on the former open questions (board #8)

1. **Job creation mode:** leave it unset by default so the server default
   applies (Java parity). Expose it as an option on the query config. Never
   opt into `JOB_CREATION_OPTIONAL` silently.
2. **insertAll insertIds:** auto-generate a UUID for each row without one
   (Go/Python/Node), which makes `insertAll` retry-safe. Callers can supply
   IDs or opt out, and opting out disables retries. This is an intentional
   difference from Java.
3. **Task cancellation:** cancelling the Swift `Task` only stops waiting or
   paging. It never sends `jobs.cancel`; server-side cancel is the explicit
   `cancelJob` method.
