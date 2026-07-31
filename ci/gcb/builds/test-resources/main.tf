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

# Create a pre-existing bucket to speed some integration tests.
resource "google_storage_bucket" "test-bucket" {
  name          = "${var.project}-test-bucket"
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
  # Remove objects older than 90d. It is unlikely that any test object is useful
  # after that long.
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

# Create a KMS Key Ring and key for the Storage examples.
resource "google_kms_key_ring" "us-central1" {
  name     = "us-central1"
  location = "us-central1"
}

# A crypto key for the Storage examples.
resource "google_kms_crypto_key" "storage-examples" {
  name     = "storage-examples"
  key_ring = google_kms_key_ring.us-central1.id
  # Rotate every 10 days
  rotation_period = "864000s"
}

# Get the service account for Cloud Storage in the current project.
data "google_storage_project_service_account" "gcs-account" {
}

# Grant Google Cloud Storage (in the project) permissions to use the example key.
resource "google_kms_crypto_key_iam_member" "storage-examples" {
  crypto_key_id = google_kms_crypto_key.storage-examples.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs-account.email_address}"
}
