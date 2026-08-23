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
import GoogleCloudAuth
import GoogleCloudGax
import GoogleCloudStorage

/// Orchestrates the execution of the W1R3 benchmark across concurrent worker tasks.
public struct BenchmarkRunner: Sendable {
  public let bucketName: String
  public let minObjectSize: Int
  public let maxObjectSize: Int
  public let taskCount: Int
  public let iterations: Int
  public let minDeleteBatch: Int
  public let maxDeleteBatch: Int
  public let rampupPeriod: Duration
  public let readCount: Int
  public let delete: Bool
  public let skipOkSamples: Bool

  public init(
    bucketName: String,
    minObjectSize: Int,
    maxObjectSize: Int,
    taskCount: Int,
    iterations: Int,
    minDeleteBatch: Int,
    maxDeleteBatch: Int,
    rampupPeriod: Duration,
    readCount: Int,
    delete: Bool,
    skipOkSamples: Bool,
  ) {
    self.bucketName = bucketName
    self.minObjectSize = minObjectSize
    self.maxObjectSize = maxObjectSize
    self.taskCount = taskCount
    self.iterations = iterations
    self.minDeleteBatch = minDeleteBatch
    self.maxDeleteBatch = maxDeleteBatch
    self.rampupPeriod = rampupPeriod
    self.readCount = readCount
    self.delete = delete
    self.skipOkSamples = skipOkSamples
  }

  public func execute() async throws {
    logToStderr(
      "# Starting W1R3 benchmark with bucket: \(bucketName), tasks: \(taskCount), iterations: \(iterations)"
    )

    let counters = BenchmarkCounters()

    logToStderr("Generating random payload buffer (\(maxObjectSize) bytes)...")
    let randomBuffer = Self.generateRandomBuffer(size: maxObjectSize)
    logToStderr("Random payload buffer ready.")

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
            buffer: randomBuffer
          )
        }
      }
      try await group.waitForAll()
    }

    let finalSummary = await counters.formattedDescription()
    logToStderr("DONE. Final \(finalSummary)")
  }

  private func runWorker(
    taskIndex: Int,
    counters: BenchmarkCounters,
    buffer: Data
  ) async {
    let clock = ContinuousClock()
    // Apply rampup delay
    if taskIndex > 0 {
      let delay = rampupPeriod * Double(taskIndex)
      try? await Task.sleep(for: delay)
    }

    let credentials: Credentials
    let storageClient: StorageClient
    let controlClient: StorageControlClient
    do {
      credentials = try Credentials()
      storageClient = try StorageClient(
        StorageClientOptions().with { $0.client = .init().with { $0.credentials = credentials } })
      controlClient = try StorageControlClient(
        ClientOptions().with { $0.credentials = credentials })
    } catch {
      logToStderr("Failed to initialize Storage clients for task \(taskIndex): \(error)")
      return
    }

    let taskStartInstant = clock.now
    var deletes = [GoogleCloudStorage.Object]()
    var batchSize =
      minDeleteBatch == maxDeleteBatch
      ? minDeleteBatch
      : Int.random(in: minDeleteBatch...maxDeleteBatch)

    for iteration in 0..<iterations {
      let size =
        minObjectSize == maxObjectSize
        ? minObjectSize
        : Int.random(in: minObjectSize...maxObjectSize)
      let objectName = Self.randomObjectName()
      let isResumable = Bool.random()
      let uploadOp: Operation = isResumable ? .resumable : .singleShot

      let uploadBuilder = SampleBuilder(
        task: taskIndex,
        taskStartInstant: taskStartInstant,
        iteration: iteration,
        op: uploadOp,
        targetSize: size,
        object: objectName
      )

      let uploadSlice = size > 0 ? buffer.prefix(size) : Data()

      var uploadedObject: GoogleCloudStorage.Object? = nil
      do {
        let object = try await StorageOperations.upload(
          client: storageClient,
          controlClient: controlClient,
          bucketName: bucketName,
          objectName: objectName,
          data: uploadSlice,
          isResumable: isResumable
        )
        uploadedObject = object
        let sample = uploadBuilder.success()
        self.emitSample(sample)
        await counters.incrementWrite()
        await counters.incrementSample()
      } catch {
        let details = await counters.errorDetails(error: error)
        let sample = uploadBuilder.error(details: details)
        self.emitSample(sample)
        await counters.incrementWrite()
        await counters.incrementWriteError()
        await counters.incrementSample()
        continue
      }

      // Download / Read loop
      for readIndex in 0..<readCount {
        let readOp = Operation.read(readIndex)
        let readBuilder = SampleBuilder(
          task: taskIndex,
          taskStartInstant: taskStartInstant,
          iteration: iteration,
          op: readOp,
          targetSize: size,
          object: objectName
        )

        let (transferSize, readError) = await StorageOperations.download(
          client: storageClient,
          bucketName: bucketName,
          objectName: objectName,
          generation: uploadedObject?.generation
        )

        if let error = readError {
          let details = await counters.errorDetails(error: error)
          if transferSize > 0 {
            let sample = readBuilder.interrupted(transferSize: transferSize, details: details)
            self.emitSample(sample)
          } else {
            let sample = readBuilder.error(details: details)
            self.emitSample(sample)
          }
          await counters.incrementRead()
          await counters.incrementReadError()
          await counters.incrementSample()
        } else {
          let sample = readBuilder.success(transferSize: transferSize)
          self.emitSample(sample)
          await counters.incrementRead()
          await counters.incrementSample()
        }
      }

      if !delete {
        continue
      }
      if let object = uploadedObject {
        deletes.append(object)
      }
      if deletes.count >= batchSize {
        // Pick the next batch size and delete the current batch.
        batchSize =
          minDeleteBatch == maxDeleteBatch
          ? minDeleteBatch
          : Int.random(in: minDeleteBatch...maxDeleteBatch)
        let currentBatch = deletes
        deletes.removeAll(keepingCapacity: true)

        await self.deleteBatch(
          taskIndex: taskIndex,
          counters: counters,
          taskStartInstant: taskStartInstant,
          iteration: iterations,
          credentials: credentials,
          batch: currentBatch
        )
      }
    }

    // Flush remaining deletes
    if delete {
      await self.deleteBatch(
        taskIndex: taskIndex,
        counters: counters,
        taskStartInstant: taskStartInstant,
        iteration: iterations,
        credentials: credentials,
        batch: deletes
      )
    }
  }

  private func deleteBatch(
    taskIndex: Int,
    counters: BenchmarkCounters,
    taskStartInstant: ContinuousClock.Instant,
    iteration: Int,
    credentials: GoogleCloudAuth.Credentials,
    batch: [GoogleCloudStorage.Object],
  ) async {
    if batch.isEmpty {
      return
    }
    let deleteBuilder = SampleBuilder(
      task: taskIndex,
      taskStartInstant: taskStartInstant,
      iteration: iteration,
      op: .delete,
      targetSize: batch.count,
      object: batch[0].name,
    )

    do {
      try await StorageOperations.batchDelete(
        credentials: credentials, batch: batch
      )
      let sample = deleteBuilder.success()
      self.emitSample(sample)
      await counters.incrementDelete()
      await counters.incrementSample()
    } catch {
      let details = await counters.errorDetails(error: error)
      let sample = deleteBuilder.error(details: details)
      self.emitSample(sample)
      await counters.incrementDelete()
      await counters.incrementDeleteError()
      await counters.incrementSample()
    }
  }

  private func emitSample(_ sample: Sample) {
    if self.skipOkSamples && sample.result == .ok {
      return
    }
    print(sample.toRow())
  }

  private static func generateRandomBuffer(size: Int) -> Data {
    guard size > 0 else { return Data() }
    // There is a lot going on here. Sometimes the benchmark is used with really large buffers,
    // 256MiB and 2GiB are not uncommon. To efficiently initialized the buffer with random data
    // we create an array of the desired size.
    let bytes = [UInt8](unsafeUninitializedCapacity: size) { buffer, initializedCount in
      var offset = 0
      while offset < size {
        // Fetch a full word at a time. We could use UInt8.random to make the code simpler, but
        // that discards 7 bytes of (expensively computed) random data.
        var val = UInt64.random(in: .min ... .max)
        let count = min(8, size - offset)
        for i in 0..<count {
          buffer[offset + i] = UInt8(truncatingIfNeeded: val)
          val >>= 8
        }
        offset += count
      }
      initializedCount = size
    }
    return Data(bytes)
  }

  private static func randomObjectName() -> String {
    let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<32).map { _ in charset.randomElement()! })
  }
}
