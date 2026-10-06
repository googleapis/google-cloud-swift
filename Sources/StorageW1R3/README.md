# Cloud Storage W1R3 Benchmark

The W1R3 benchmark measures single-stream upload and download throughput and latency for the Cloud Storage Swift client library. The benchmark writes one object and reads it three times (or `--read-count` times), recording high-precision timing, transfer sizes, and checksum validation metrics.

## Automated Deployment on GCE (Recommended)

The easiest way to deploy and run the benchmark is using the turnkey deployment script:
[`Sources/StorageW1R3/scripts/run-w1r3-gce.sh`](scripts/run-w1r3-gce.sh).

This script automates:
1. **Infrastructure setup**: Creating a regional GCS bucket with optimal configuration (hierarchical namespace, uniform bucket-level access, auto-deletion lifecycle rule).
2. **VM provisioning**: Launching a [Compute-Optimized][compute-optimized] GCE VM (e.g. `c2d-standard-8`) with high [network bandwidth][network bandwidth].
3. **Environment & compilation**: Automatically installing dependencies and building `StorageW1R3Benchmark` in release mode.
4. **Execution & metrics collection**: Running the benchmark, streaming live logs to your console, and uploading CSV results and logs to Cloud Storage.
5. **BigQuery ingestion**: Automatically loading results into a BigQuery dataset for immediate query and analysis.
6. **Teardown**: Automatically shutting down and deleting the GCE VM upon completion to prevent unnecessary compute charges.

### Prerequisites

Ensure you have the Google Cloud CLI (`gcloud`, `bq`) installed and authenticated. The `jq` utility is recommended for inspecting BigQuery datasets.

```shell
gcloud auth login
gcloud auth application-default login
gcloud config set project <YOUR_PROJECT_ID>
```

### Quickstart Examples

#### 1. Quick Smoke Test
Run a quick test with 2 workers and 10 iterations:

```shell
./Sources/StorageW1R3/scripts/run-w1r3-gce.sh \
    --task-count 2 \
    --iterations 10
```

#### 2. High-Throughput Performance Benchmark
Benchmark larger 16MiB objects using a 16-vCPU compute-optimized machine:

```shell
./Sources/StorageW1R3/scripts/run-w1r3-gce.sh \
    --machine-type c2d-standard-16 \
    --task-count 16 \
    --iterations 200 \
    --min-object-size 16MiB \
    --max-object-size 16MiB
```

#### 3. Test Local Uncommitted or Unpushed Changes
To benchmark changes you are developing locally without having to push them to GitHub first, use `--stage-local`:

```shell
./Sources/StorageW1R3/scripts/run-w1r3-gce.sh \
    --stage-local \
    --task-count 4 \
    --iterations 50
```

#### 4. Unattended / Asynchronous Execution
To launch the VM and exit immediately without waiting:

```shell
./Sources/StorageW1R3/scripts/run-w1r3-gce.sh \
    --async \
    --task-count 8 \
    --iterations 500
```

You can view execution anytime by running:
```shell
gcloud compute instances tail-serial-port-output <INSTANCE_NAME> --zone=<ZONE>
```

### Deployment Script Options

| Option | Default | Description |
|---|---|---|
| `--project` | Current gcloud project | GCP Project ID |
| `--zone` | `us-central1-a` | GCE zone |
| `--region` | Derived from zone | GCP region |
| `--machine-type` | `c4-standard-192` | GCE machine type (default: `c4-standard-192`) |
| `--bucket` | `w1r3-<PROJECT>-<REGION>` | Cloud Storage test bucket name (has 1-day auto-delete lifecycle) |
| `--results-bucket` | `w1r3-results-<PROJECT>-<REGION>` | Cloud Storage bucket for persistent CSV results and logs |
| `--bq-dataset` | `w1r3` | BigQuery dataset name |
| `--bq-table` | `swift_<RUN_ID>` | BigQuery table name |
| `--git-repo` | Current git origin | Git repository URL |
| `--git-ref` | Current git commit | Git branch, commit, or tag |
| `--stage-local` | `false` | Tar and stage local working tree to GCS |
| `--task-count` | `4` | Number of concurrent worker tasks |
| `--iterations` | `100` | Number of iterations per worker |
| `--min-object-size` | `0` | Minimum object size (e.g. `0`, `128KiB`, `1MiB`) |
| `--max-object-size` | `128KiB` | Maximum object size (e.g. `128KiB`, `16MiB`) |
| `--read-count` | `3` | Number of read operations per object |
| `--client-count` | `1` | Number of `StorageClient` instances |
| `--crc32c` | `always` | Checksum mode: `always`, `random`, or `never` |
| `--extra-args` | `""` | Additional CLI flags passed to `StorageW1R3Benchmark` |
| `--no-wait` / `--async` | `false` | Launch VM and exit without tailing output |
| `--keep-vm` | `false` | Prevent VM deletion after benchmark completion |

---

## Analyzing Benchmark Results in BigQuery

Results are loaded into BigQuery with the following schema:

| Column | Type | Description |
|---|---|---|
| `Task` | `INT64` | Worker task index (0-based) |
| `Iteration` | `INT64` | Iteration number for the task |
| `IterationStart` | `INT64` | Microseconds since task start |
| `Operation` | `STRING` | Operation: `Upload`, `ResumableUpload`, `Read[0]`, `Read[1]`, `Read[2]`, `Delete` |
| `Size` | `INT64` | Target object size in bytes |
| `TransferSize` | `INT64` | Actual bytes transferred |
| `ElapsedMicroseconds` | `INT64` | Wall-clock execution time in microseconds |
| `Object` | `STRING` | Random object name generated for the iteration |
| `Crc32cEnabled` | `BOOL` | Whether CRC32C checksum validation was enabled |
| `Result` | `STRING` | Status: `OK`, `ERROR`, or `INTERRUPTED` |
| `Details` | `STRING` | Error details or additional notes |

### Sample Analysis Queries

#### Throughput and Latency Percentiles by Operation

```sql
SELECT
  Operation,
  COUNT(*) as sample_count,
  ROUND(AVG(TransferSize / (1024 * 1024)), 2) as avg_size_mib,
  ROUND(AVG((TransferSize * 8.0) / ElapsedMicroseconds), 2) as avg_throughput_mbps,
  ROUND(APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(50)], 2) as p50_latency_ms,
  ROUND(APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(90)], 2) as p90_latency_ms,
  ROUND(APPROX_QUANTILES(ElapsedMicroseconds / 1000.0, 100)[OFFSET(99)], 2) as p99_latency_ms
FROM `<PROJECT_ID>.w1r3.<TABLE_NAME>`
WHERE Result = 'OK'
GROUP BY Operation
ORDER BY Operation;
```

#### Upload vs. Read Bandwidth by Object Size Bucket

```sql
SELECT
  Operation,
  CASE
    WHEN Size < 256 * 1024 THEN '< 256KiB'
    WHEN Size < 1024 * 1024 THEN '256KiB - 1MiB'
    WHEN Size < 8 * 1024 * 1024 THEN '1MiB - 8MiB'
    ELSE '>= 8MiB'
  END AS size_bucket,
  COUNT(*) as count,
  ROUND(AVG((TransferSize * 8.0) / ElapsedMicroseconds), 2) as avg_mbps
FROM `<PROJECT_ID>.w1r3.<TABLE_NAME>`
WHERE Result = 'OK'
GROUP BY Operation, size_bucket
ORDER BY Operation, MIN(Size);
```

---

## Manual Execution (Alternative)

If you prefer to configure and run the benchmark manually on an existing VM:

1. **Create the bucket** (in the same region as the VM):
   ```shell
   echo '{ "rule": [ { "action": {"type": "Delete"}, "condition": {"age": 1} } ] }' > lf.json
   gcloud storage buckets create \
     --enable-hierarchical-namespace --uniform-bucket-level-access \
     --soft-delete-duration=0s --lifecycle-file=lf.json \
     --location=${REGION} gs://${BUCKET_NAME}
   ```

2. **Build and run `StorageW1R3Benchmark`**:
   ```shell
   TS=$(date +%s)
   GOOGLE_CLOUD_SWIFT_LOCAL_DEPS=1 swift run -c release StorageW1R3Benchmark \
     --bucket-name "${BUCKET_NAME}" \
     --max-object-size 128KiB \
     --task-count 4 \
     --iterations 100 \
     > "bm-${TS}.txt" 2> "bm-${TS}.log"
   ```

3. **Upload to BigQuery**:
   ```shell
   bq load --source_format CSV --skip_leading_rows 1 \
     ${GOOGLE_CLOUD_PROJECT}:w1r3.swift001 bm-${TS}.txt \
     Task:int64,Iteration:int64,IterationStart:int64,Operation,Size:int64,TransferSize:int64,ElapsedMicroseconds:int64,Object,Crc32cEnabled:bool,Result,Details
   ```

[compute-optimized]: https://cloud.google.com/compute/docs/compute-optimized-machines
[network bandwidth]: https://cloud.google.com/compute/docs/network-bandwidth
