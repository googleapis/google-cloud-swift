# ``GoogleCloudBigQuery``

A Swift client for [BigQuery](https://cloud.google.com/bigquery).

## Overview

BigQuery is a serverless data warehouse. Use this library to run GoogleSQL
queries, read and stream table data, and manage datasets, tables, routines,
models, and jobs.

Create one ``BigQueryClient`` and share it across tasks:

```swift
import GoogleCloudBigQuery

let client = try BigQueryClient()
```

The client uses Application Default Credentials and finds its project from
``BigQueryClientOptions/projectID`` or the `GOOGLE_CLOUD_PROJECT` environment variable.
Resource IDs without a project, such as `TableID(datasetID: "d", tableID: "t")`, refer to
the client's project.

Read the rows of a table as an `AsyncSequence`. The first page is fetched before
``BigQueryClient/listRows(in:schema:selectedFields:startIndex:pageSize:pageToken:options:)``
returns, and later pages are fetched as you iterate:

```swift
let rows = try await client.listRows(in: TableID(datasetID: "d", tableID: "t"))
for try await row in rows {
  if let name = try row["name"]?.stringValue {
    print(name)
  }
}
```

Use ``Row/decode(_:)`` or ``RowSequence/decode(_:)`` to decode rows into your own
`Decodable` types, and
``BigQueryClient/insertAll(_:into:skipInvalidRows:ignoreUnknownValues:templateSuffix:insertIDs:options:)``
to stream rows into a table.

<!-- TODO(slice 4): add the query example from README.md once bq-jobs merges. -->

Get operations return `nil` when the resource does not exist, and delete operations return
`false`. Other failures reported by the service, or by a job, are thrown as
``BigQueryError``. Requests are retried on transient errors when they are safe to repeat;
see ``BigQueryRetryPolicy``.

## Topics

### Essentials

- ``BigQueryClient``
- ``BigQueryClientOptions``
- ``BigQueryError``
- ``BigQueryRetryPolicy``

### Identifiers

- ``DatasetID``
- ``TableID``
- ``RoutineID``
- ``ModelID``
- ``JobID``

### Tables

- ``Table``
- ``TableType``
- ``TableMetadataView``
- ``StreamingBuffer``
- ``TimePartitioning``
- ``RangePartitioning``
- ``Clustering``
- ``EncryptionConfiguration``
- ``TableConstraints``
- ``PrimaryKey``
- ``ForeignKey``
- ``ColumnReference``

### Views, snapshots, and clones

- ``ViewDefinition``
- ``MaterializedViewDefinition``
- ``SnapshotDefinition``
- ``CloneDefinition``
- ``UserDefinedFunction``

### External and BigLake tables

- ``ExternalDataConfiguration``
- ``DataFormat``
- ``CSVOptions``
- ``ParquetOptions``
- ``AvroOptions``
- ``GoogleSheetsOptions``
- ``BigtableOptions``
- ``BigtableColumnFamily``
- ``BigtableColumn``
- ``HivePartitioningOptions``
- ``DecimalTargetType``
- ``FileSetSpecType``
- ``ObjectMetadata``
- ``MetadataCacheMode``
- ``BigLakeConfiguration``

### Rows and schemas

- ``Schema``
- ``Field``
- ``FieldType``
- ``Row``
- ``FieldValue``
- ``RowSequence``

### Values

- ``BigNumeric``
- ``BigQueryDate``
- ``BigQueryTime``
- ``BigQueryDateTime``
- ``Interval``
- ``BigQueryRange``

### Streaming inserts

- ``InsertRow``
- ``InsertValue``
- ``InsertIDPolicy``
- ``InsertAllResponse``

### Queries

- ``QueryParameters``
- ``QueryParameterValue``
- ``QueryParameterType``
- ``QueryParameterConvertible``
- ``JobCreationMode``

<!-- TODO(slice 4): add QueryJobConfiguration, QueryResult, QueryDryRunResult, and the
query option types. Add a "Jobs" group with Job, JobStatus, JobStatistics,
JobConfiguration, LoadJobConfiguration, CopyJobConfiguration, ExtractJobConfiguration,
and UploadSource. -->

### Datasets

- ``Dataset``
- ``Acl``
- ``ExternalDatasetReference``
- ``DatasetView``
- ``DatasetUpdateMode``

### Routines and models

- ``Routine``
- ``StandardSQLDataType``
- ``StandardSQLField``
- ``StandardSQLStructType``
- ``StandardSQLTableType``
- ``Model``

### Projects and access control

- ``Project``
- ``IAMPolicy``
- ``Expr``

### Pagination

- ``PagedSequence``
- ``Page``
