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
import NIOCore
import GoogleCloudAuth
import GoogleCloudGax
import GoogleCloudStorage

/// Orchestrates the execution of the W1R3 benchmark across concurrent worker tasks.
extension StorageW1R3 {
  func runWorker(
    taskIndex: Int,
    counters: BenchmarkCounters,
    buffer: NIOCore.ByteBuffer
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
    let pickBatchSize = { () -> Int in
      if minDeleteBatch == maxDeleteBatch { return minDeleteBatch }
      return Int.random(in: minDeleteBatch...maxDeleteBatch)
    }
    let pickObjectSize = { () -> Int in
      if minObjectSize == maxObjectSize { return minObjectSize }
      return Int.random(in: minObjectSize...maxObjectSize)
    }
    var batchSize = pickBatchSize()

    for iteration in 0..<iterations {
      let size = pickObjectSize()
      let objectName = Self.randomObjectName()
      let isResumable = Bool.random()
      let uploadSlice = buffer.getSlice(at: 0, length: size) ?? buffer.slice()
      let iterationId = IterationId(
        task: taskIndex, taskStartInstant: taskStartInstant, iteration: iteration)

      guard
        let uploadedObject = await self.sampleUpload(
          iterationId: iterationId,
          counters: counters,
          storageClient: storageClient,
          controlClient: controlClient,
          bucketName: bucketName,
          objectName: objectName,
          buffer: uploadSlice,
          isResumable: isResumable)
      else {
        continue
      }

      for readIndex in 0..<readCount {
        await self.sampleDownload(
          iterationId: iterationId,
          counters: counters,
          readIndex: readIndex,
          client: storageClient,
          object: uploadedObject,
          size: size)
      }

      if self.noDelete {
        continue
      }
      deletes.append(uploadedObject)
      if deletes.count >= batchSize {
        batchSize = pickBatchSize()
        let currentBatch = deletes
        deletes.removeAll(keepingCapacity: true)

        await self.deleteBatch(
          iterationId: iterationId,
          counters: counters,
          client: controlClient,
          batch: currentBatch
        )
      }
    }

    if self.noDelete {
      return
    }
    // Flush remaining deletes
    await self.deleteBatch(
      iterationId: IterationId(
        task: taskIndex, taskStartInstant: taskStartInstant, iteration: iterations),
      counters: counters,
      client: controlClient,
      batch: deletes
    )
  }

  private func sampleUpload(
    iterationId: IterationId,
    counters: BenchmarkCounters,
    storageClient: StorageClient,
    controlClient: StorageControlClient,
    bucketName: String,
    objectName: String,
    buffer: NIOCore.ByteBuffer,
    isResumable: Bool
  ) async -> GoogleCloudStorage.Object? {
    let uploadOp: Operation = isResumable ? .resumable : .singleShot

    let uploadBuilder = SampleBuilder(
      iterationId: iterationId,
      op: uploadOp,
      targetSize: buffer.readableBytes,
      object: objectName
    )
    do {
      let object = try await StorageOperations.upload(
        client: storageClient,
        controlClient: controlClient,
        bucketName: bucketName,
        objectName: objectName,
        buffer: buffer,
        isResumable: isResumable
      )
      let sample = uploadBuilder.success()
      self.emitSample(sample)
      await counters.incrementWrite()
      await counters.incrementSample()
      return object
    } catch {
      let details = await counters.errorDetails(error: error)
      let sample = uploadBuilder.error(details: details)
      self.emitSample(sample)
      await counters.incrementWrite()
      await counters.incrementWriteError()
      await counters.incrementSample()
    }
    return nil
  }

  private func sampleDownload(
    iterationId: IterationId,
    counters: BenchmarkCounters,
    readIndex: Int,
    client: StorageClient,
    object: GoogleCloudStorage.Object,
    size: Int,
  ) async {
    let readOp = Operation.read(readIndex)
    let readBuilder = SampleBuilder(
      iterationId: iterationId,
      op: readOp,
      targetSize: size,
      object: object.name
    )

    let (transferSize, readError) = await StorageOperations.download(client: client, object: object)

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

  private func deleteBatch(
    iterationId: IterationId,
    counters: BenchmarkCounters,
    client: StorageControlClient,
    batch: [GoogleCloudStorage.Object],
  ) async {
    if batch.isEmpty {
      return
    }
    let deleteBuilder = SampleBuilder(
      iterationId: iterationId,
      op: .delete,
      targetSize: batch.count,
      object: batch[0].name,
    )

    do {
      try await StorageOperations.batchDelete(
        client: client, batch: batch
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

  func generateRandomBuffer() -> NIOCore.ByteBuffer {
    let size = self.maxObjectSize
    var buffer = ByteBufferAllocator().buffer(capacity: size)
    guard size > 0 else { return buffer }
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
    buffer.writeBytes(bytes)
    return buffer
  }

  private static func randomObjectName() -> String {
    let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<32).map { _ in charset.randomElement()! })
  }
}
