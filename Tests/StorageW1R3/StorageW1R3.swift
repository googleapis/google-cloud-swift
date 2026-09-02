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

import ArgumentParser
import Foundation
import GoogleCloudAuth
import GoogleCloudStorage

@main
struct StorageW1R3: AsyncParsableCommand, Sendable {
  static let configuration = CommandConfiguration(
    commandName: "StorageW1R3",
    abstract: "W1R3 Benchmark for Google Cloud Storage Swift client library.",
    discussion: """
      This program is a benchmark for the Google Cloud Storage client library.

      The benchmark uploads an object and reads it multiple times (default 3), reporting the time it
      takes to perform each of these operations to stdout. Usually the results are analyzed using an
      external script or coLab notebook.

      The benchmark runs multiple concurrrent tasks performing all these operations. This reduces
      the time to collect enough samples for statistical analysis. If running the benchmark with
      hundreds or a few thousand tasks, consider a rampup period between them to avoid contention
      on the credentials and other resources used during initialization (e.g. DNS).

      To avoid biasing the results, the benchmark randomizes the upload size, the type of upload
      (resumable vs. single-shot), and even the name of the object. This also removes some of the
      problems associated with seasonal / diurnal variation in performance for the service.

      If you want to use an specific object size, set the range accordingly.

      The benchmark cleans up after itself by deleting the objects it creates. Deleting these
      objects can become a bottleneck when using many small objects. The benchmark can be configured
      to delete the objects in batches. The size of the batch is selected at random, from a range
      specified in the commend line. You can also disable deletion altogether.
      """
  )

  func run() async throws {
    logToStderr(
      "# Starting W1R3 benchmark with bucket: \(bucketName), tasks: \(taskCount), iterations: \(iterations)"
    )

    let counters = BenchmarkCounters()

    logToStderr("Generating random payload buffer (\(maxObjectSize) bytes)...")
    let randomBuffer = self.generateRandomBuffer()
    logToStderr("Random payload buffer ready.")

    let credentials = try Credentials()
    let storageClients = try self.makeClients(credentials)
    let controlClients = try self.makeControlClients(credentials)
    logToStderr("Clients initialzed ready.")

    // Print CSV header to stdout.
    print(Sample.header)

    // Start a background task to periodically report the counters to stderr.
    let monitorTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        if Task.isCancelled { break }
        let summary = await counters.formattedDescription()
        logToStderr(summary)
      }
    }
    defer {
      monitorTask.cancel()
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for taskIndex in 0..<taskCount {
        group.addTask {
          await self.runWorker(
            taskIndex: taskIndex,
            counters: counters,
            buffer: randomBuffer,
            storageClient: storageClients[taskIndex % storageClients.count],
            controlClient: controlClients[taskIndex % controlClients.count],
          )
        }
      }
      try await group.waitForAll()
    }

    let finalSummary = await counters.formattedDescription()
    logToStderr("DONE. Final \(finalSummary)")
  }

  @Option(
    name: .customLong("bucket-name"),
    help: "The name of the GCS bucket used by the benchmark."
  )
  var bucketName: String

  @Option(
    name: .customLong("min-object-size"),
    help: "The minimum object size (e.g. 0, 128KiB, 1MiB).",
    transform: SizeParser.parse
  )
  var minObjectSize: Int = 0

  @Option(
    name: .customLong("max-object-size"),
    help: "The maximum object size (e.g. 128KiB, 1MiB, 16MiB).",
    transform: SizeParser.parse
  )
  var maxObjectSize: Int = 128 * 1024

  @Option(
    name: .customLong("task-count"),
    help: "The number of concurrent tasks running the benchmark."
  )
  var taskCount: Int = 1

  @Option(
    name: .customLong("iterations"),
    help: "The number of iterations for each task."
  )
  var iterations: Int = 1

  @Option(
    name: .customLong("min-delete-batch"),
    help: "The minimum size for the delete batch."
  )
  var minDeleteBatch: Int = 20

  @Option(
    name: .customLong("max-delete-batch"),
    help: "The maximum size for the delete batch."
  )
  var maxDeleteBatch: Int = 20

  @Option(
    name: .customLong("rampup-period"),
    help: "The rampup period between new tasks (e.g. 500ms).",
    transform: DurationParser.parse
  )
  var rampupPeriod: Duration = .milliseconds(500)

  @Option(
    name: .customLong("read-count"),
    help: "Sets the number of reads on each object."
  )
  var readCount: Int = 3

  @Flag(
    name: .customLong("no-delete"),
    help: "Skip deleting objects after the test."
  )
  var noDelete: Bool = false

  @Flag(
    name: .customLong("skip-ok-samples"),
    help: "Only print samples that failed."
  )
  var skipOkSamples: Bool = false

  @Option(
    name: .customLong("client-count"),
    help: "Number of storage clients."
  )
  var clientCount: Int = 1

  @Option(
    name: .customLong("control-client-count"),
    help: "Number of storage control clients."
  )
  var controlClientCount: Int = 1

  func validate() throws {
    guard minObjectSize <= maxObjectSize else {
      throw ValidationError(
        "Invalid object size range: min (\(minObjectSize)) > max (\(maxObjectSize))")
    }
    guard minDeleteBatch <= maxDeleteBatch else {
      throw ValidationError(
        "Invalid delete batch size range: min (\(minDeleteBatch)) > max (\(maxDeleteBatch))")
    }
    guard taskCount >= 1 else {
      throw ValidationError("task-count must be at least 1")
    }
    guard iterations >= 1 else {
      throw ValidationError("iterations must be at least 1")
    }
    guard readCount >= 0 else {
      throw ValidationError("read-count must be non-negative")
    }
    guard clientCount >= 1 else {
      throw ValidationError("client-count must be at least 1")
    }
    guard controlClientCount >= 1 else {
      throw ValidationError("control-client-count must be at least 1")
    }
  }
}
