# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "project" {
  type = string
}

variable "region" {
  type = string
}

# Create a bucket to cache build artifacts.
resource "google_storage_bucket" "build-cache" {
  name          = "${var.project}-build-cache"
  force_destroy = false
  # This prevents Terraform from deleting the bucket. Any plan to do so is
  # rejected. If we really need to delete the bucket we must take additional
  # steps.
  lifecycle {
    prevent_destroy = true
  }

  # The bucket configuration.
  location                    = "US-CENTRAL1"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  versioning {
    enabled = false
  }
  # Remove objects older than 90d. It is unlikely that any build artifact is
  # useful after that long, and we can always rebuild them if needed.
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

# The e2-standard-8 images schedule faster than the e2-standard-32 images.
#
# For builds that don't need a lot of CPUs, it is beneficial to use a smaller
# machine type.
resource "google_cloudbuild_worker_pool" "pool" {
  name     = "swift-sdk-pool"
  location = "us-central1"
  worker_config {
    disk_size_gb   = 256
    machine_type   = "e2-standard-8"
    no_external_ip = false
  }
}

# Some builds can use the extra parallelism afforded by the 32 cores.
resource "google_cloudbuild_worker_pool" "pool32" {
  name     = "swift-sdk-pool-large"
  location = "us-central1"
  worker_config {
    disk_size_gb   = 256
    machine_type   = "e2-standard-32"
    no_external_ip = false
  }
}

output "build-cache" {
  value = resource.google_storage_bucket.build-cache.id
}
