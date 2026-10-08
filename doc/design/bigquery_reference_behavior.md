# BigQuery Java Reference: Behavioral Contract

This document records how the Java BigQuery client behaves, not only what it
offers. The Swift port (`pkgs/swift-google-cloud-bigquery`, module
`GoogleCloudBigQuery`) is checked against it. Each statement cites the Java
source at the `google-cloud-java` checkout.

## Citation legend

All paths are relative to the `google-cloud-java` repository root.

| Alias | Path |
| ----- | ---- |
| `J/`  | `java-bigquery/google-cloud-bigquery/src/main/java/com/google/cloud/bigquery/` |
| `JR/` | `java-bigquery/google-cloud-bigquery/src/main/java/com/google/cloud/bigquery/spi/v2/` |
| `T/`  | `java-bigquery/google-cloud-bigquery/src/test/java/com/google/cloud/bigquery/` |
| `C/`  | `sdk-platform-java/java-core/google-cloud-core/src/main/java/com/google/cloud/` |
| `CH/` | `sdk-platform-java/java-core/google-cloud-core-http/src/main/java/com/google/cloud/http/` |

`Impl` is short for `J/BigQueryImpl.java` and `Rpc` is short for
`JR/HttpBigQueryRpc.java`.

Statements marked **(inferred)** come from reading the code paths. No test
pins them down.

---

## 1. Client construction

### Options and defaults

- **OAuth scope:** `https://www.googleapis.com/auth/bigquery`
  (`J/BigQueryOptions.java:L38-39`).
- **Transport:** only HTTP transport is accepted. Any other transport throws
  `IllegalArgumentException` (`J/BigQueryOptions.java:L88-95`).
- **Read timeout:** the default HTTP read timeout is 60000 ms, set through
  `HttpTransportOptions` (`J/BigQueryOptions.java:L37`, `L214-216`).
- **JWT access:** `setUseJwtAccessWithScope(false)` is forced
  (`J/BigQueryOptions.java:L80-82`).
- **`location`:** an optional client-wide default location
  (`J/BigQueryOptions.java:L97-100`, `L227`). It is used as follows:
  - It fills `JobId.location` for generated job IDs and for get, cancel, and
    getQueryResults calls (§4, §7).
  - It is the location for fast-path `jobs.query` (§5).
  - It is **not** used for datasets. The server picks the dataset default.
- **`resultRetryAlgorithm`:** defaults to
  `BigQueryBaseService.DEFAULT_BIGQUERY_EXCEPTION_HANDLER`
  (`J/BigQueryOptions.java:L178-182`).
- **`DataFormatOptions`:** the default is built from the deprecated
  `useInt64Timestamps` flag (`J/BigQueryOptions.java:L184-191`).
- **`throwNotFound`:** defaults to `false`. When `true`, the get methods throw
  on 404 instead of returning `null` (`J/BigQueryOptions.java:L236-238`,
  `L266`).
- **`defaultJobCreationMode`:** defaults to `JOB_CREATION_MODE_UNSPECIFIED`
  (`J/BigQueryOptions.java:L46`, setter `L262`).
- **OpenTelemetry:** tracing is controlled by flags
  (`J/BigQueryOptions.java:L146-159`). Every request also sends the header
  `x-goog-otel-enabled` (see `Rpc`).

### Project and credential discovery (`C/ServiceOptions.java`)

- **projectId:** taken from the builder, otherwise from `getDefaultProjectId()`.
  If neither yields a project, construction throws `IllegalArgumentException`
  (`L353-359`).
- **Project discovery order (`L430-443`):**
  1. `GOOGLE_CLOUD_PROJECT` system property or environment variable.
  2. Legacy `GCLOUD_PROJECT`.
  3. App Engine.
  4. `project_id` in the credentials file.
  5. gcloud config (`L462-509`).
  6. GCE metadata server.
- **Credentials:** taken from the builder, otherwise Application Default
  Credentials. If ADC fails, credentials are `null` (`L362`, `L401-407`).
- **quotaProjectId:** taken from the builder, otherwise from the credentials
  file field `quota_project_id` (`L379-382`).

### Endpoint and universe domain

- `DEFAULT_HOST` is `https://www.googleapis.com` (`C/ServiceOptions.java:L86`).
- `getResolvedApiaryHost("bigquery")` returns `https://bigquery.{universeDomain}/`
  unless a custom host is set (`C/ServiceOptions.java:L898-905`). The default
  universe is `googleapis.com`.
- `HttpBigQueryRpc` uses the resolved host as the root URL
  (`Rpc:L115-132`).
- **Universe check:** before every RPC, `validateRPC()` compares the
  configured universe domain with the credentials' universe. On mismatch it
  throws `BigQueryException(401, "The configured universe domain ... does not
  match ...")` (`Rpc:L138-146`, `C/ServiceOptions.java:L915-919`).

### Headers

- **User-Agent:** `[<custom UA> ]gcloud-java/<version>`
  (`C/ServiceOptions.java:L700-718`). The custom part comes from the header
  provider (`L750-759`).
- **`x-goog-api-client`:** uses the library name `gccl`
  (`C/ServiceOptions.java:L726-728`).
- **`prettyPrint=false`:** added to every request (`Rpc`, per request
  builder).

### Request timeouts

- The HTTP read timeout is 60 s (above).
- Default `RetrySettings` (`C/ServiceOptions.java:L808-818`):

  | Setting | Default |
  | ------- | ------- |
  | maxAttempts | 6 |
  | initialRetryDelay | 1 s |
  | retryDelayMultiplier | 2.0 |
  | maxRetryDelay | 32 s |
  | totalTimeout | 50 s |
  | initial/max RPC timeout | 50 s |

---

## 2. Retries

### Machinery

- **`BigQueryRetryHelper.runWithRetries`** (`J/BigQueryRetryHelper.java:L49-91`):
  - Combines `ExponentialRetryAlgorithm(retrySettings)` with
    `BigQueryRetryAlgorithm`.
  - Unwraps the `RetryHelperException`. If the cause is an `IOException`, it
    is rethrown as `new BigQueryException(IOException)` (`L80-85`).
- **Default exception handler** (`J/BigQueryBaseService.java:L29-36`):
  - Aborts on `RuntimeException`.
  - Retries on `ConnectException`, `UnknownHostException`, and
    `SocketException`.
  - Its interceptor (`C/BaseService.java:L30-50`) also retries any
    `BaseServiceException` whose `isRetryable()` is true.
  - Any exception not listed is **not** retried
    (`C/ExceptionHandler.java:L236-257`).
- **`maybeWrapForHttpRetry`** (`J/BigQueryRetryHelper.java:L133-138`,
  `L145-166`):
  - Applies only when the configured algorithm is the default handler.
  - Adds retry of raw `HttpResponseException` with status 500, 502, 503,
    or 504.
  - A custom `resultRetryAlgorithm` is left untouched.
- **`BigQueryRetryAlgorithm.shouldRetry`** (`J/BigQueryRetryAlgorithm.java:L60-95`):
  - Retries when (the result algorithm says retry **or** the error message
    matches the `BigQueryRetryConfig`) **and** the timing algorithm still
    allows another attempt.
  - **Message matching (`L97-141`):** the message is lowercased. A
    `retryOnMessage` entry matches if it is a substring (`contains`). A
    `retryOnRegEx` entry must match the whole lowercased message
    (`Pattern.matches`, no DOTALL) (`L143-146`).
  - **(inferred)** On the `*SkipExceptionTranslation` paths the throwable is
    a raw `GoogleJsonResponseException`. Its message spans several lines
    (`"403 Forbidden\nPOST ...\n{json}"`). Because the regex has no DOTALL
    and must match the whole message, it effectively never matches there.
    Only the substring messages do. This argues for reason-based detection
    in Swift.
  - It also inspects **successful responses**. If a 200 response is a `Job`
    whose `status.errorResult.message` matches the config, the call is
    retried (`L219-231`).

### Retry configs

- `EMPTY_RETRY_CONFIG` and `DEFAULT_RETRY_CONFIG` are defined at
  `Impl:L648-656`. `DEFAULT_RETRY_CONFIG` contains:
  - Messages: `"Exceeded rate limits:"` and `"Job exceeded rate limits:"`.
  - Regex: `".*exceed.*rate.*limit.*"`.
  - Source: `J/BigQueryErrorMessages.java:L18-25`.
- `Job.DEFAULT_RETRY_CONFIG` contains only `"Exceeded rate limits:"`
  (`J/Job.java:L83-86`).
- These calls use `DEFAULT_RETRY_CONFIG`:
  - `jobs.insert` (`Impl:L960-968`). A `JobOption.bigQueryRetryConfig` can
    override it, and `RetryOptions` are merged in.
  - `jobs.query` (`Impl:L2438`, `L2582`, `L2857`).
  - `getQueryResults` (`Impl:L3321`).
- All other calls use `EMPTY_RETRY_CONFIG`.

### What is NOT retried

- **No reason-based retry.** The main sources never reference the reasons
  `rateLimitExceeded`, `backendError`, or `jobRateLimitExceeded`. Rate
  limiting is detected only through the message text above.
- **No job-level re-run.** A query job that fails with a retryable error is
  never re-run with a new job ID.
- `BigQueryException.isRetryable()` depends only on the HTTP code: 500, 502,
  503, 504, with any reason (`J/BigQueryException.java:L39-41`). A 429 or 403
  `rateLimitExceeded` is retried only if its message matches the retry config.

### Per-RPC behavior

| Calls | Retry behavior (default handler) |
| ----- | -------------------------------- |
| Wrapped reads and lists: getDataset `Impl:L1060`, listDatasets `L1126`, getTable `L1599`, getModel `L1658`, getRoutine `L1717`, listTables `L1935`, listModels `L1976`, listRoutines `L2017`, listTableData `L2198`, getJob `L2275`, listJobs `L2332`, cancel `L2387`, getQueryResults `L3319`, getIamPolicy `L3390`, testIamPermissions `L3484`, and **createRoutine** `L864` | Network exceptions, HTTP 500/502/503/504, and message-config matches. |
| Unwrapped calls: create dataset `L687-699`, create table `L800-812`, create job `L940-970`, all deletes `L1169-1182` `L1221-1231` `L1267-1277` `L1313-1323` `L1359-1367`, patch/update `L1396-1408` `L1443-1455` `L1489-1501` `L1535-1547`, setIamPolicy `L3427-3440`, jobs.query `L2426-2440` | Network exceptions and message-config matches. **(inferred)** HTTP 5xx is not retried in production, because the `*SkipExceptionTranslation` RPCs throw raw `GoogleJsonResponseException`. Unit tests mock these RPCs to throw `BigQueryException(5xx)`, which *is* retried. |
| listProjects `Impl:L731-773` | Uses the translating RPC, so `BigQueryException` 5xx is retried through the interceptor. |
| insertAll `Impl:L2040-2118` | Retried **only if every row has an `insertId`**, otherwise a single attempt (comment at `L2041-2044`). |
| Write channel open and chunk upload (`J/TableDataWriteChannel.java:L68-84`, `L116-133`) | Default handler, no wrapping. |

### Idempotency and job IDs

- **`jobs.insert` without a user `JobId`:** every attempt generates a fresh
  random `JobId.of()` with location set to `options.location` and project set
  to the options project (`Impl:L879-891`, `L944-952`).
- **On a failed insert with a user-supplied JobId** (`Impl:L978-1005`):
  - If the error message matches `.*Already.*Exists:.*Job.*`
    (case-insensitive), the client calls `getJob(id, fields=STATISTICS)`.
  - It returns that job if `creationTime` is within the last 24 hours, so a
    retried insert returns the original job.
- **On a failed insert with a random JobId** (`Impl:L1008-1021`): the client
  tries `getJob(lastGeneratedId)`. If the job exists it is returned, otherwise
  the original error is rethrown.
- **`jobs.query`:** `requestId` is a random UUID generated **once per
  `query()` call**, so it is stable across retries
  (`J/QueryRequestInfo.java:L63`). This is tested by
  `T/BigQueryImplTest.java:L3974-4019`.

---

## 3. Errors

### `BigQueryException` (`J/BigQueryException.java`)

- `RETRYABLE_ERRORS` are codes 500, 502, 503, and 504 with any reason
  (`L39-41`). Every constructor marks the exception idempotent.
- **`BigQueryException(List<BigQueryError>)`** (`L60-68`): code 0, with the
  message and reason taken from the first error. Used for job errors and
  `jobs.query` `errors`.
- **`BigQueryException(IOException)`** (`L70-79`): builds a single
  `BigQueryError(reason, location, message, debugInfo)` when the parsed
  response has a reason.
- `getError()` returns the first error (`L85-87`).
- `translateAndThrow` variants are at `L120-140`. `UNKNOWN_CODE` is 0.
- **HTTP parsing** (`CH/BaseHttpServiceException.java:L40-84`):
  - From a `GoogleJsonResponseException`: `code` is the HTTP status,
    `reason`, `location`, and `debugInfo` come from `errors[0]`, and `message`
    is `error.message`.
  - From a non-JSON response: the status code and status message.
  - `IOException` retryability applies when the call is idempotent. Retryable
    cases are `SocketTimeoutException`, `SocketException`, SSL connection
    shutdown, non-certificate handshake failures, `"insufficient data
    written"`, and `"Error writing request body to server"`.

### `BigQueryError` (`J/BigQueryError.java`)

- Fields: `reason`, `location`, `message`, and `debugInfo` (`L53-70`).
- `equals` compares `toPb()` (`L110-114`). `hashCode` excludes `debugInfo`
  (`L96-99`).

### Job errors

- `Job.reload()` and `waitFor` throw `BigQueryException` when the job has
  `status.errorResult`. The thrown exception carries `executionErrors`
  (`status.errors`) if present, otherwise `errorResult`
  (`J/Job.java:L612-639`).
- `Job.getQueryResults()` also throws on job error (`J/Job.java:L360-478`).
- On the `jobs.query` fast path, a non-null `response.errors` throws
  `BigQueryException(errors)` (`Impl:L2449-2455`).

### 404 handling

`Impl:L3553-3560` decides whether an error is a 404.

| Operation | Result on 404 |
| --------- | ------------- |
| getDataset, getTable, getJob, getModel, getRoutine | Return `null`. When `options.throwNotFound` is set, throw `BigQueryException(404, "Dataset not found" / "Table not found" / "Job not found" ...)` instead (`Impl:L1066-1072`, `L1606-1610`, `L2282-2286`). |
| delete dataset, table, model, routine | Return `false` (`Impl:L1184-1186`, `L1235-1236`, `L1281-1282`, `L1327-1328`). |
| cancel(JobId) | Returns `false` (`Impl:L2393-2394`). |
| delete(JobId) | **No 404 special-casing:** the error propagates as `BigQueryException` (`Impl:L1339-1376`). |
| Job.exists / Job.isDone | `exists` is false when not found (`J/Job.java:L179-196`). `isDone()` returns **true** when the job is not found (`J/Job.java:L214-235`). |
| Job.waitFor | Returns `null` if the job no longer exists (`J/Job.java:L341`). |

---

## 4. Operations on the `BigQuery` interface

### Common rules

- **Options:** passing the same option twice throws `IllegalArgumentException`
  (`Impl:L3502-3509`). RPC query-parameter names are listed in
  `JR/BigQueryRpc.java:L45-66`.
- **Field masks:** the `fields(...)` options always add required fields.

  | Resource | Always included | Source |
  | -------- | --------------- | ------ |
  | Dataset | `datasetReference` | `J/BigQuery.java:L65-66` |
  | Table | `tableReference`, `type` | `J/BigQuery.java:L145-146` |
  | Model | `modelReference` | `J/BigQuery.java:L195` |
  | Routine | `routineReference` | `J/BigQuery.java:L227-228` |
  | Job | `jobReference`, `configuration` | `J/BigQuery.java:L258-259` |

  The JobListOption mask is `jobs(...)` and also adds `state` and
  `errorResult` (`J/BigQuery.java:L643-646`). Selector helpers are in
  `C/FieldSelector.java:L59-111`.
- **Project defaulting:**
  - `DatasetId`, `TableId`, and `JobId` `setProjectId` fill the project only
    if it is null.
  - String overloads use the options project.
  - Table, model, and routine create/update/get/delete fill the project when
    it is null or empty.

### Update (PATCH) semantics: unset, clear, or value

- **Null setters clear fields.** A builder turns a `null` setter value into
  an explicit JSON `null`, which clears the field on PATCH:

  | Builder | Fields | Source |
  | ------- | ------ | ------ |
  | TableInfo | description, expirationTime, friendlyName | `J/TableInfo.java:L287-305` |
  | DatasetInfo | defaultTableLifetime, description, friendlyName, location | `J/DatasetInfo.java:L313-349` |
  | RoutineInfo | description | `J/RoutineInfo.java:L270` |
  | Field | description | `J/Field.java:L214` |

- **TimePartitioning** always sends `expirationMs`. When it is unset, the
  value is `Data.NULL_LONG` (a JSON null) (`J/TimePartitioning.java:L131`).
- **Labels** (`J/Annotations.java:L40-60`):
  - A null map is sent as JSON `null`, which clears all labels.
  - An empty map is omitted from the request.
  - A null value for a key deletes that key.
- The Swift update API needs this three-way distinction between unset,
  clear, and value.
- **No optimistic concurrency.** Java never sends an `etag` or `If-Match` on
  any patch or update. `Rpc` has no etag handling, so updates are
  last-writer-wins.

### Datasets

| Op | HTTP | Behavior |
| -- | ---- | -------- |
| create | `POST /projects/{p}/datasets` (`Rpc:L318-357`) | Project comes from the dataset reference, otherwise the options project (`Impl:L664-671`). Options: `fields`, `accessPolicyVersion`. |
| get | `GET /projects/{p}/datasets/{d}` (`Rpc:L162-204`) | Options: `fields`, `accessPolicyVersion`, `datasetView`. Project is filled by `setProjectId(options project)` (`Impl:L1036`). |
| list | `GET /projects/{p}/datasets` (`Rpc:L216-263`) | Options: `all`, `filter`, `maxResults`, `pageToken`. Items are **partial** datasets with only reference, friendlyName, id, kind, location, and labels (`Rpc:L101-113`). |
| update | `PATCH /projects/{p}/datasets/{d}` (`Rpc:L628-671`) | Options: `accessPolicyVersion`, `updateMode` (`datasetUpdateMode`). Project default at `Impl:L1380-1382`. |
| delete | `DELETE /projects/{p}/datasets/{d}` (`Rpc:L569-616`) | Option: `deleteContents`. Returns `false` on 404. Project default at `Impl:L1155`. |

### Tables

| Op | HTTP | Behavior |
| -- | ---- | -------- |
| create | `POST /projects/{p}/datasets/{d}/tables` (`Rpc:L369-411`) | Clears the output-only `type` (`Rpc:L372-373`). Whenever `externalDataConfiguration` is non-null, `table.schema` is overwritten with `externalDataConfiguration.schema`, even when that schema is null (`Impl:L822-830`). |
| get | `GET .../tables/{t}` (`Rpc:L744-785`) | `view` defaults to **`STORAGE_STATS`** (`Rpc:L787-792`). Option: `fields`. |
| list | `GET .../tables` (`Rpc:L805-868`) | Items are partial tables with friendlyName, id, kind, reference, type, creationTime, timePartitioning, rangePartitioning, clustering, and labels (`Rpc:L851-866`). Project default at `Impl:L1763`. String overload at `Impl:L1752-1753`. |
| update | `PATCH .../tables/{t}` (`Rpc:L683-727`) | Clears `type`. Options: `fields`, `autodetectSchema`. Same external-schema move as create. |
| delete | `DELETE .../tables/{t}` (`Rpc:L884-916`) | Returns `false` on 404. |
| listPartitions | Uses `tabledata.list` | Reads the meta-table `{table}$__PARTITIONS_SUMMARY__` and returns the `partition_id` column as strings (`Impl:L1877-1908`). |

### Models and routines

- **Models:**
  - patch: `PATCH .../models/{m}` (`Rpc:L928-945`).
  - get: `GET .../models/{m}` (`Rpc:L988-997`).
  - list: `GET .../models` (`Rpc:L1042-1051`). Project default at
    `Impl:L1809`.
  - delete: `DELETE .../models/{m}` (`Rpc:L1105-1135`). Returns `false` on
    404.
  - There is no model create; models are created by queries.
- **Routines:**
  - create: `POST .../routines` (`Rpc:L423-463`). Retried with HTTP 5xx
    wrapping (`Impl:L864`).
  - update: **`PUT`** `.../routines/{r}`, a full replace (`Rpc:L1149-1162`).
  - get: `GET .../routines/{r}` (`Rpc:L1211-1220`).
  - list: `GET .../routines` (`Rpc:L1265-1274`). Project default at
    `Impl:L1855`.
  - delete: `DELETE .../routines/{r}` (`Rpc:L1327-1357`). Returns `false` on
    404.

### Jobs

| Op | HTTP | Behavior |
| -- | ---- | -------- |
| create | `POST /projects/{p}/jobs` (`Rpc:L476-517`) | Project is the job reference project, otherwise the options project (`Rpc:L478-481`). Option: `fields`. Job ID generation and recovery are described in §2. The query variant `createJobForQuery` sends no `fields` (`Rpc:L529-566`). `createConnection` is at `Impl:L893-906`. |
| get | `GET /projects/{p}/jobs/{j}?location=` (`Rpc:L1540-1549`) | Fills project and location from the options when unset (`Impl:L2241-2249`). Returns `null` on 404. |
| list | `GET /projects/{p}/jobs` (`Rpc:L1643-1666`) | Always uses the options project (`Impl:L2328`). Options: `allUsers`, `fields`, `stateFilter`, `maxResults`, `pageToken`, `parentJobId`, `minCreationTime`, `maxCreationTime`. Always sends `projection=full`. List items fill `status.state` and `errorResult` from the list entry (`Rpc:L1695-1720`). |
| cancel | `POST /projects/{p}/jobs/{j}/cancel?location=` (`Rpc:L1737-1765`) | Fills project and location from the options (`Impl:L2359-2366`). Returns `false` on 404, otherwise `true`. |
| delete | `DELETE /projects/{p}/jobs/{j}/delete?location=` (`Rpc:L1779-1807`) | Fills the **project only**, not the location (`Impl:L1339-1344`). There is no 404 translation (`Rpc:L1770-1775`). |
| getQueryResults | `GET /projects/{p}/queries/{j}` (`Rpc:L1822-1865`) | Params: `location`, `maxResults`, `pageToken`, `startIndex`, `timeoutMs`. Fills project and location from the options (`Impl:L3296-3302`). Returns `QueryResponse(completed, schema, totalRows or 0, errors)` (`Impl:L3269-3343`). |
| query | `POST /projects/{p}/queries` (`Rpc:L1930-1956`) | See §5. |

### Table data

- **insertAll:** `POST .../tables/{t}/insertAll` (`Rpc:L1372-1405`).
  - `ignoreUnknownValues`, `skipInvalidRows`, and `templateSuffix` are copied
    to the request (`Impl:L2052-2055`).
  - Each row is sent as `{insertId?, json}` (`Impl:L2060-2073`).
  - The response maps row index to a list of errors
    (`J/InsertAllResponse.java:L45-64`).
- **listTableData:** `GET .../tables/{t}/data` (`Rpc:L1418-1462`).
  - Options: `maxResults`, `pageToken`, `startIndex`.
  - Returns `TableResult(schema, totalRows, rows)` (`Impl:L2144-2165`).
  - Rows are parsed with `FieldValueList.fromPb(row, schemaFields,
    useInt64Timestamp)` (`Impl:L2220-2232`).

### IAM (tables only)

The resource name is `projects/{p}/datasets/{d}/tables/{t}`
(`J/TableId.java:L68-71`).

- **getIamPolicy:** `POST .../tables/{t}:getIamPolicy`, with
  `options.requestedPolicyVersion` (`Rpc:L2056-2088`).
- **setIamPolicy:** `POST ...:setIamPolicy` (`Rpc:L2100-2125`).
- **testIamPermissions:** `POST ...:testIamPermissions` (`Rpc:L2137-2163`).
  Returns an **empty list** when the response has no permissions
  (`Impl:L3489-3491`).

### Resumable upload (`writer`)

- **`writer(JobId, WriteChannelConfiguration)`:**
  - The `JobId` defaults to `JobId.of()`.
  - The project is set from the options (`Impl:L3346-3357`).
- **Open** (`Rpc:L1968-1983`):
  - Request: `POST {root}/upload/bigquery/v2/projects/{options project}/jobs?uploadType=resumable`
    with the Job JSON body, which contains the load configuration and
    `jobReference` (`J/TableDataWriteChannel.java:L100-141`).
  - Header: `X-Upload-Content-Value: application/octet-stream`
    (`Rpc:L1980`). This is a Java typo for `X-Upload-Content-Type`. **Do not
    copy it.**
  - Returns the `Location` header as the upload URL.
- **Write** (`Rpc:L2002-2044`):
  - Request: `PUT {uploadUrl}` with
    `Content-Range: bytes {off}-{off+len-1}/{total | *}`.
  - A non-final chunk expects status **308**.
  - The final chunk expects **200 or 201** and parses the `Job` from the
    body.
  - **Any** zero-length write returns `null` without sending a request, even
    when `last=true` (`Rpc:L2005-2007`). A zero-byte final chunk therefore
    never finalizes the upload.
- **Chunk size:** the default is 15 MiB (60 × 256 KiB) and the minimum is
  256 KiB (`C/BaseWriteChannel.java:L39-40`).
- After `close()`, `getJob()` returns the created load job
  (`J/TableDataWriteChannel.java:L151-153`).

### Pagination

- `PageImpl` uses a `NextPageFetcher` for each resource
  (`Impl:L90-249`).
- **listTableData next pages:** the fetcher keeps only `startIndex(0)` and
  the `pageToken`. **The original options, such as `maxResults`, are
  dropped** (`Impl:L2203-2214`).
- `TableResult.getNextPage()` does not carry `jobId` forward
  (`J/TableResult.java:L183-205`).
- Values are attached to the schema through `withSchema`
  (`J/TableResult.java:L207-229`).

---

## 5. Query path

### `query(config, [jobId], options)`: `queryWithTimeout` (`Impl:L2718-2789`)

1. **Dry-run check:** a dry-run config throws
   `UnsupportedOperationException` (`Impl:L2721`, `J/Job.java:L682-702`).
   Use `create(JobInfo)` for dry runs.
2. **Creation mode:** a null `JobCreationMode` takes
   `options.defaultJobCreationMode` (`Impl:L2724-2729`).
3. **Fast path (`jobs.query`):** taken iff
   `QueryRequestInfo.isFastQuerySupported()` (no arguments) and
   (`jobId == null` or `jobId.job == null`). The job ID check is inline at
   `Impl:L2751`. When taken:
   - Project is `jobId.project`, otherwise the options project
     (`Impl:L2756-2759`).
   - Location is `jobId.location`, otherwise `options.location`
     (`Impl:L2766-2770`).
   - `timeoutMs` is sent only when `queryWithTimeout` receives a non-null
     timeout (`Impl:L2771-2773`). Plain `query()` passes `null`
     (`Impl:L2710`), so it sends no `timeoutMs` and the server default
     applies.
   - The ARROW format branches off (`Impl:L2775-2782`).
4. **Slow path:** `create(JobInfo.of(jobId, config))`, then
   `job.getQueryResults()` (`Impl:L2708-2715`).

### Fast-path eligibility (`J/QueryRequestInfo.java:L87-100`)

- The fast path is **disallowed** if any of these fields is set:
  - clustering
  - createDisposition
  - destinationEncryptionConfiguration
  - destinationTable
  - maximumBillingTier
  - priority
  - rangePartitioning
  - schemaUpdateOptions
  - tableDefinitions
  - timePartitioning
  - userDefinedFunctions
  - writeDisposition
- `allowLargeResults` and `flattenResults` do **not** disqualify the fast
  path. They are silently dropped.

### QueryRequest fields (`J/QueryRequestInfo.java:L102-156`)

- The request carries these fields:
  - connectionProperties
  - defaultDataset
  - dryRun
  - labels
  - maximumBytesBilled
  - maxResults
  - query
  - requestId
  - queryParameters, with `parameterMode` NAMED or POSITIONAL
  - createSession
  - useLegacySql
  - useQueryCache
  - jobCreationMode
  - reservation
  - jobTimeoutMs
  - formatOptions
  - queryResultsFormat
  - arrowSerializationOptions
- `formatOptions{useInt64Timestamp, timestampOutputFormat}` is **always**
  sent.
- `JobCreationMode` values (`J/QueryJobConfiguration.java:L103-114`):
  - `JOB_CREATION_MODE_UNSPECIFIED` is treated by the server as REQUIRED.
  - `JOB_CREATION_REQUIRED`.
  - `JOB_CREATION_OPTIONAL`: stateless queries. The response may have no
    `jobReference`, only a `queryId`.
- `jobCreationMode` is not part of the job configuration
  (`J/QueryJobConfiguration.java:L1134-1232`).

### Fast-path response handling: `queryRpc` (`Impl:L2410-2511`)

- **Not complete:** if `jobComplete` is false or `schema` is null, the client
  fetches the job (`getJob`) and continues on the slow path with
  `job.getQueryResults()` (`Impl:L2459-2475`).
- **Row count:** `numRows` is `numDmlAffectedRows`, otherwise `totalRows`,
  otherwise 0 (`Impl:L2536-2544`). DML results report affected rows as the
  total.
- **Paging:** if the response has a `pageToken`, a `QueryPageFetcher` is used
  (`Impl:L251-286`, `L2477-2494`). For subsequent pages it reloads the job
  **every 5 s until DONE**, then calls `tabledata.list` on the destination
  table with the page token. With no page token the result is a single page
  (`Impl:L2496-2510`).
- The `QueryPageFetcher` constructor calls `getJob` immediately
  (`Impl:L260-271`). That adds an extra RPC whenever the first fast-path
  page has a `pageToken`.
- **Result metadata:** `TableResult` carries queryId, jobCreationReason,
  statementType, totalBytesProcessed, totalSlotMs, numDmlAffectedRows,
  sessionInfo, and cacheHit (`Impl:L2513-2534`).

### Waiting and polling (`J/Job.java`)

- **Wait settings:**

  | Settings | Total timeout | Initial delay | Backoff | Max delay | Jitter | Source |
  | -------- | ------------- | ------------- | ------- | --------- | ------ | ------ |
  | `DEFAULT_JOB_WAIT_SETTINGS` | 12 h | 1 s | ×2 | 1 min | yes | `L59-66` |
  | `DEFAULT_QUERY_JOB_WAIT_SETTINGS` | 12 h | 3 s | constant | 3 s | yes | `L68-75` |

- **Quirk:** `waitFor` picks the settings in reverse. Query jobs use the
  *job* settings and non-query jobs use the *query* settings
  (`L330-339`).
- **Query jobs:** `waitFor` polls `getQueryResults(maxResults=0)` until
  `completed`, retrying on the rate-limit message (`L77-79`, `L480-529`).
- **Other jobs:** `waitFor` polls `getJob(fields=STATUS)` until DONE
  (`L531-585`).
- When done, `waitFor` returns `reload()`, or `null` if the job is gone
  (`L341`).
- **`Job.getQueryResults(options)`** (`L360-478`):
  - Maps `pageSize`, `pageToken`, and `startIndex` to `tabledata.list`, and
    `TIMEOUT` to the maximum wait time.
  - Throws on job error.
  - **Shortcut:** if `totalRows == 0`, it returns an empty `TableResult`
    without calling `tabledata.list`. This covers DDL such as `CREATE VIEW`,
    where no destination table exists (`L432-452`).
  - Otherwise it calls `listTableData` on the destination table with the
    schema and attaches the job statistics (`L454-472`).

### Arrow / Read API (Java only; may be deferred in Swift)

- **Entry points:** `queryRpcArrow` (`Impl:L2559-2705`) and `queryArrow`
  (`Impl:L2792-3011`).
- **`queryArrow` defaults:**
  - The creation mode defaults to `JOB_CREATION_OPTIONAL`.
  - The fast path additionally requires that no options are passed.
- **`ArrowQueryPageFetcher`** (`Impl:L300-502`):
  - Reads the Storage Read API stream
    `projects/{p}/locations/{loc}/jobs/{job}/streams/_default`.
  - Location comes from the job, otherwise the options, otherwise `"US"`.
  - The default page size is 10000 rows. The page token is the row offset.
- **Read client cache:** one Read client per location, at most 100 clients
  (`Impl:L504-577`). The clients are closed in `close()` (`Impl:L602-620`).
- **Other Arrow helpers:**
  - Table read: `createArrowQueryResultFromTable` creates a ReadSession with
    `maxStreamCount=1` (`Impl:L3024-3059`).
  - `readArrowTableResultFromJob` (`Impl:L3072-3244`).
  - Fallback: `queryFallbackArrow` (`Impl:L3258-3266`).
- **Connection API** (`createConnection`, `Impl:L893-906`):
  - A JDBC-like layer over jobs.query, getQueryResults, and the Read API.
  - Not part of the core contract.

---

## 6. Data conversion

### Cell parsing: `FieldValue.fromPb` (`J/FieldValue.java:L386-422`)

| JSON cell | Result |
| --------- | ------ |
| JSON null (`Data.isNull`) | PRIMITIVE with a null value |
| String | PRIMITIVE, or RANGE if the schema field is RANGE with an element type |
| List | REPEATED; each element is a `{"v": ...}` wrapper, unwrapped |
| Map with `"f"` | RECORD, recursing with the subfields |
| Map with `"v"` | Unwrapped |
| Anything else | `IllegalArgumentException("Unexpected table cell format")` |

The four attributes are PRIMITIVE, REPEATED, RECORD, and RANGE
(`J/FieldValue.java:L57-76`).

**Quirk: REPEATED elements lose the schema.** REPEATED cells are parsed with
a `null` schema (`J/FieldValue.java:L401-405`, `J/FieldValueList.java:L118-131`).
As a result:

- Elements of an `ARRAY<STRUCT>` have no schema, so `get(name)` on them
  throws `UnsupportedOperationException`.
- Elements of an `ARRAY<RANGE>` come back as PRIMITIVE strings, not RANGE.

Swift should fix this and record it as an intentional difference.

### Getters (`J/FieldValue.java`)

- **INTEGER** arrives as a JSON **string**. `getLongValue` uses
  `Long.parseLong` (`L176-178`).
- `getStringValue`: `L132-135`.
- `getDoubleValue`: `L189-191`.
- `getBooleanValue`: accepts `true`/`false` case-insensitively and throws
  `IllegalStateException` otherwise (`L202-208`).
- `getBytesValue`: base64 decode, `IllegalStateException` on bad input
  (`L159-165`).
- `getNumericValue`: `new BigDecimal(string)`, used for NUMERIC and
  BIGNUMERIC (`L259-261`).
- **`getTimestampValue` (micros)** (`L220-232`):
  - In int64 mode, `BigInteger` micros.
  - Otherwise the value is float seconds, scaled ×1e6 with `HALF_UP`
    rounding.
- `getTimestampInstant`: `L244-247`.
- `getRangeValue`: `L272-278`. `getRepeatedValue`: `L289-292`.
  `getRecordValue`: `L324-327`.
- **`getPeriodDuration` (INTERVAL)** (`L305-314`, `L434-481`): parses ISO-8601
  first, otherwise the canonical `Y-M D H:M:S[.F]` form.
- DATE, TIME, DATETIME, GEOGRAPHY, and JSON are returned as strings
  verbatim.
- **`FieldValueList`** (`J/FieldValueList.java`):
  - A row whose size differs from the schema throws
    `IllegalArgumentException`.
  - `get(name)` without a schema throws `UnsupportedOperationException`.

### Timestamp formats (`J/DataFormatOptions.java:L27-72`)

- `TimestampFormatOptions` values: `UNSPECIFIED`, `FLOAT64`, `INT64`, and
  `ISO8601_STRING`.
- With `ISO8601_STRING`, values are returned verbatim, with up to picosecond
  precision (`T/it/ITHighPrecisionTimestamp.java:L79-86`, `L127-144`).
- `Field.setTimestampPrecision` accepts only 6 or 12
  (`J/Field.java:L266-272`).

### RANGE (`J/Range.java:L101-134`)

- `Range.of` parses `"[start, end)"` by splitting on `", "`.
- `UNBOUNDED` and `NULL` bounds become null.

### `QueryParameterValue` serialization (`J/QueryParameterValue.java`)

- **TIMESTAMP:**
  - Output format is `yyyy-MM-dd HH:mm[:ss[.ffffff..fffffffff]][+HH:MM]` in
    UTC (`L82-99`).
  - A `Long` is treated as micros and formatted (`L500-505`).
  - A `String` is validated, with up to 12 fractional digits; strings without
    `T` are accepted (`L506-512`, `L553-577`).
- **DATE, TIME, DATETIME:**
  - DATE: `yyyy-MM-dd`.
  - TIME: `HH:mm:ss.SSSSSS`.
  - DATETIME: `yyyy-MM-dd HH:mm:ss.SSSSSS`.
  - Sources: `L115-119`, `L514-537`.
- **Other scalars:**
  - BYTES: base64 (`L480-483`).
  - NUMERIC and BIGNUMERIC: `BigDecimal.toString()` (`L474-478`).
  - A null value is sent as a null string (`L455-457`).
- **Quirks:**
  - In the value switch, the `JSON` case has no `break` and falls through to
    `INTERVAL` (`L489-493`).
  - `classToType(String)` always returns STRING. The GEOGRAPHY and JSON
    branches are unreachable (`L427-452`).
- **ARRAY** (`L400-414`):
  - Elements are QPVs.
  - The type of an array of structs comes from the first element
    (`L633-643`).
- **STRUCT** (`L420-425`, `L644-653`): field types come from the values, and
  field order is preserved.
- **RANGE:** value and type serialization at `L611-626` and `L654-660`.
- **Named vs. positional:** a config uses one or the other, never both
  (`J/QueryJobConfiguration.java:L315-399`, `L755-765`).

### insertAll row encoding

- A row is a `Map<String, ?>` and null values are allowed
  (`J/InsertAllRequest.java:L84-95`).
- The docs recommend sending NUMERIC values as strings and BYTES as base64
  (`J/InsertAllRequest.java:L56-73`).

### Schema and type mapping

- **`LegacySQLTypeName` ↔ `StandardSQLTypeName`**
  (`J/LegacySQLTypeName.java:L48-119`):
  - INTEGER ↔ INT64
  - FLOAT ↔ FLOAT64
  - BOOLEAN ↔ BOOL
  - RECORD ↔ STRUCT
  - Other names are the same.
- `legacySQLTypeName(ARRAY)` returns null (`L121-144`).
- Standard type enum: `J/StandardSQLTypeName.java:L28-63`, which includes
  RANGE.
- **`Field`** (`J/Field.java`):
  - A RECORD requires subfields, and a non-RECORD forbids them
    (`L172-187`).
  - `toPb` writes the legacy type name (`L507-546`). `fromPb` is at
    `L548-588`.
  - `mode` is null when unset and is treated as NULLABLE (`L206`,
    `L358-361`).

---

## 7. Job lifecycle

### JobId (`J/JobId.java`)

- `JobId.of()` creates a random UUID job ID (`L78-80`, `L101-103`).
- `of(project, job)` validates its arguments (`L88-98`).
- `setProjectId` and `setLocation` fill the value only if it is null
  (`L105-111`).
- `JobInfo.setProjectId` propagates the project into the configuration
  (`J/JobInfo.java:L313-319`). `toPb` is at `L321-339`.

### Job status and dispositions

- **JobStatus** (`J/JobStatus.java:L39-86`):
  - States are PENDING, RUNNING, and DONE.
  - Unknown values are accepted through `valueOf`.
  - The job's error is `errorResult`, and `executionErrors` holds
    `status.errors`.
- **Dispositions** (`J/JobInfo.java:L56-91`):
  - Create: `CREATE_IF_NEEDED`, `CREATE_NEVER`.
  - Write: `WRITE_TRUNCATE`, `WRITE_TRUNCATE_DATA`, `WRITE_APPEND`,
    `WRITE_EMPTY`.
  - Schema update: `ALLOW_FIELD_ADDITION`, `ALLOW_FIELD_RELAXATION`.

### QueryJobConfiguration defaults (`J/QueryJobConfiguration.java`)

- **Builder defaults:**
  - `useLegacySql` defaults to **false** (`L136`).
  - Priority is unset, so the server uses INTERACTIVE (`L83-92`).
  - An empty query is rejected (`L1235-1237`).
- **`setProjectId`** fills the project of `destinationTable` and
  `defaultDataset` (`L1122-1131`).
- **`toPb`** (`L1134-1232`):
  - `dryRun` is always set on `JobConfiguration`.
  - `jobTimeoutMs`, `labels`, and `reservation` live at the
    `JobConfiguration` level.
- **Other fields:**
  - `setConnectionProperties`: `L670-673`.
  - `maxResults` is used only on the fast path (`L675-687`).
- **Load, Extract, and Copy configs:** the client applies no defaults beyond
  the builders. For example, Extract `format` is only set when specified
  (`J/ExtractJobConfiguration.java:L152-153`), and the server chooses CSV.

---

## 8. Quirks and edge cases

- **Empty and DDL results:** when `totalRows == 0`, the client returns an
  empty result without calling `tabledata.list` (`J/Job.java:L432-452`).
- **DML:** `numDmlAffectedRows` takes precedence over `totalRows` on the fast
  path (`Impl:L2536-2544`).
- **Inverted wait settings:** query and non-query jobs use each other's wait
  settings (`J/Job.java:L330-339`).
- **Fast-path drops:** `allowLargeResults` and `flattenResults` are silently
  ignored on the fast path (`J/QueryRequestInfo.java:L87-100`).
- **Deleting a missing job:** `delete(JobId)` throws on 404, while the other
  deletes return `false` (`Impl:L1339-1376`).
- **`isDone()` of a deleted job is true** (`J/Job.java:L214-235`).
- **`createRoutine` is retried on HTTP 5xx**, but the other creates are not
  (`Impl:L864`).
- **`tables.get` returns storage statistics** because of the default
  `view=STORAGE_STATS` (`Rpc:L787-792`).
- **Next pages of listTableData drop the caller's options**
  (`Impl:L2203-2214`).
- **Partial list items:** the dataset, table, and job lists return partial
  resources. Use `reload()` or `get` for full metadata (`Rpc:L101-113`,
  `L851-866`, `L1695-1720`).
- **Rate-limit detection is message-based and case-insensitive.** It also
  applies to a 200 Job response that carries an `errorResult`
  (`J/BigQueryRetryAlgorithm.java:L97-146`, `L219-231`).
- **Sessions:** `createSession` is sent on jobs.query.
  `connectionProperties` (for example `session_id`) are passed through, and
  `sessionInfo` is surfaced on `TableResult` (`J/QueryRequestInfo.java:L102-156`,
  `Impl:L2513-2534`).
- **Scripts and child jobs:** `listJobs(parentJobId)` lists the child jobs of
  a script (`Rpc:L1643-1666`).

---

## Notable behaviors observed in tests

- **`requestId` is stable across retries:**
  `testFastQueryRateLimitIdempotency` (`T/BigQueryImplTest.java:L3974-4019`).
  The same `requestId` is sent on every retried `jobs.query`.
- **Fast-path 5xx retry:** `testFastQuerySQLShouldRetry`
  (`T/BigQueryImplTest.java:L3892-3930`).
- **Retryable 5xx on reads:** `testGetDatasetRetryableException`
  (`T/BigQueryImplTest.java:L3827-3841`).
- **501 is not retryable:** `testNonRetryableException`
  (`T/BigQueryImplTest.java:L3844-3858`).
- **`RuntimeException` aborts immediately:** `testRuntimeException`
  (`T/BigQueryImplTest.java:L3861-3874`).
- **Rate-limit regex retry:** `testRateLimitRegEx`
  (`T/BigQueryImplTest.java:L4022-4044`).
- **High-precision timestamps:** ISO-8601 output is returned verbatim with
  picoseconds (`T/it/ITHighPrecisionTimestamp.java:L79-86`, `L127-144`).
