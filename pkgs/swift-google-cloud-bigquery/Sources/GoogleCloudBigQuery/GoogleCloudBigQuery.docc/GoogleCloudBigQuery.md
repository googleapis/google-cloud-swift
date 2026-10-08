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

Read the rows of a table or a query result as an `AsyncSequence`, or decode them into a
`Decodable` type with ``RowSequence/decode(_:)``:

```swift
let result = try await client.query(
  "SELECT name, age FROM `d.people` WHERE age >= @age",
  parameters: .named(["age": .int64(18)]))
for try await row in result.rows {
  if let name = row["name"]?.stringValue {
    print(name)
  }
}
```

Use ``BigQueryClient/listRows(in:schema:selectedFields:startIndex:pageSize:pageToken:options:)``
to read a table directly without running a query, and ``InsertRow`` with `insertAll(_:into:)`
to stream rows into a table.

Get operations return `nil` when the resource does not exist, and delete operations return
`false`. Other failures reported by the service, or by a job, are thrown as
``BigQueryError``. Requests are retried on transient errors when they are safe to repeat;
see ``BigQueryRetryPolicy``.

## Topics

### Essentials

- ``BigQueryClient``
- ``BigQueryProtocol``
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
- ``BigQueryTimestamp``
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

- ``QueryJobConfiguration``
- ``QueryResult``
- ``QueryDryRunResult``
- ``QueryParameters``
- ``QueryParameterValue``
- ``QueryParameterType``
- ``QueryParameterConvertible``
- ``QueryPriority``
- ``JobCreationMode``
- ``ConnectionProperty``
- ``ScriptOptions``
- ``KeyResultStatementKind``

### Jobs

- ``Job``
- ``JobState``
- ``JobStatus``
- ``JobConfiguration``
- ``LoadJobConfiguration``
- ``UploadSource``
- ``CopyJobConfiguration``
- ``CopyOperationType``
- ``ExtractJobConfiguration``
- ``ExtractCompression``
- ``CreateDisposition``
- ``WriteDisposition``
- ``SchemaUpdateOption``
- ``ColumnNameCharacterMap``
- ``JSONExtension``

### Job statistics

- ``JobStatistics``
- ``QueryStatistics``
- ``StatementType``
- ``QueryStage``
- ``TimelineSample``
- ``DMLStats``
- ``ExportDataStatistics``
- ``SearchStatistics``
- ``MetadataCacheStatistics``
- ``TableMetadataCacheUsage``
- ``UndeclaredQueryParameter``
- ``ScriptStatistics``
- ``TransactionInfo``
- ``SessionInfo``
- ``LoadStatistics``
- ``CopyStatistics``
- ``ExtractStatistics``

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
