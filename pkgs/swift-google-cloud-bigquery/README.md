# Google Cloud Client Libraries for Swift - BigQuery API

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-cloud-bigquery%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/googleapis/swift-google-cloud-bigquery)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-cloud-bigquery%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/googleapis/swift-google-cloud-bigquery)

BigQuery is a serverless, highly scalable data warehouse. Analyze large
datasets with GoogleSQL queries, and store and stream data into managed tables.

## Overview

This library implements an idiomatic Swift client for the BigQuery API.

Use `BigQueryClient` for all operations. Create one client and share it across
tasks. By default it uses [Application Default Credentials] and finds its
project from `BigQueryClientOptions.projectID` or the `GOOGLE_CLOUD_PROJECT`
environment variable.

- Run queries with `query(_:parameters:options:)`. Iterate the rows of the
  result as an `AsyncSequence` of `Row`, or decode them into your own
  `Decodable` types.
- Stream rows into a table with `insertAll(_:into:)`, or load data with load
  jobs.
- Manage [datasets], [tables], views, materialized views, external tables,
  routines, and models. Read the rows of a table with `listRows(in:)`.
- Run, monitor, and cancel query, load, copy, and extract jobs.

Every list operation returns a `PagedSequence`, which fetches pages lazily as
you iterate. Errors from the service or from a failed job are thrown as
`BigQueryError`.

[Application Default Credentials]: https://docs.cloud.google.com/docs/authentication/application-default-credentials
[datasets]: https://docs.cloud.google.com/bigquery/docs/datasets-intro
[tables]: https://docs.cloud.google.com/bigquery/docs/tables-intro

## Quickstart

The following example creates a dataset and a table, streams rows into the table,
and queries it:

<!-- TODO(slice 4): `query` is on the bq-jobs branch. Re-check this example after it
merges. -->

```swift
import GoogleCloudBigQuery

struct Person: Codable {
  var name: String
  var age: Int64
}

public func quickstart(datasetID: String) async throws {
  let client = try BigQueryClient()

  // Create a dataset and a table.
  let dataset = DatasetID(datasetID: datasetID)
  _ = try await client.createDataset(Dataset(id: dataset, location: "US"))
  let tableID = dataset.table("people")
  try await client.createTable(
    Table(
      id: tableID,
      schema: [Field("name", .string, mode: .required), Field("age", .int64)]))

  // Stream rows into it.
  let response = try await client.insertAll(
    [try InsertRow(Person(name: "Ana", age: 31)), try InsertRow(Person(name: "Ben", age: 17))],
    into: tableID)
  for (index, errors) in response.rowErrors {
    print("row \(index) failed: \(errors)")
  }

  // Run a query and iterate the rows.
  let result = try await client.query(
    "SELECT name, age FROM `\(datasetID).people` WHERE age >= @age",
    parameters: .named(["age": .int64(18)]))
  for try await row in result.rows {
    if let name = try row["name"]?.stringValue {
      print(name)
    }
  }

  // Or decode the rows into a `Decodable` type.
  let people = try await client.query("SELECT name, age FROM `\(datasetID).people`")
  for try await person in people.rows.decode(Person.self) {
    print("\(person.name) is \(person.age)")
  }
}
```

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-cloud-bigquery` as a package dependency:

<!-- TODO: set the version once the first release is published. -->

```bash
swift package add-dependency https://github.com/googleapis/swift-google-cloud-bigquery.git --from 0.1.0
```

Then add `GoogleCloudBigQuery` to your target's dependencies:

```bash
swift package add-target-dependency GoogleCloudBigQuery <target-name> --package swift-google-cloud-bigquery
```

## Troubleshooting

For questions, bug reports, or feature requests, please open an issue in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift/issues) repository.

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
