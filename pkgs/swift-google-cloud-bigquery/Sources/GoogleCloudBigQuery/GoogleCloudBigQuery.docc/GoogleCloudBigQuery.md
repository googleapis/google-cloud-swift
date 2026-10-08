# ``GoogleCloudBigQuery``

A Swift client for [BigQuery](https://cloud.google.com/bigquery).

## Overview

Create one ``BigQueryClient`` and share it across tasks:

```swift
import GoogleCloudBigQuery

let client = try BigQueryClient()
```

The client uses Application Default Credentials and finds its project from
``BigQueryClientOptions/projectID`` or the `GOOGLE_CLOUD_PROJECT` environment variable.

Failures reported by the service, or by a job, are thrown as ``BigQueryError``.

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

### Rows and schemas

- ``Schema``
- ``Field``
- ``FieldType``
- ``Row``
- ``FieldValue``
- ``RowSequence``

### Pagination

- ``PagedSequence``
- ``Page``
