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

variable "project" {}

locals {
  services = [
    "aiplatform.googleapis.com",
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "dns.googleapis.com",
    "firestore.googleapis.com",
    "cloudkms.googleapis.com",
    "language.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "workflows.googleapis.com",
    "speech.googleapis.com",
    "storage.googleapis.com",
    "sqladmin.googleapis.com",
    "telemetry.googleapis.com",
    "cloudtrace.googleapis.com",
  ]
}

resource "google_project_service" "services" {
  for_each = toset(local.services)

  project = var.project
  service = each.value

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}
