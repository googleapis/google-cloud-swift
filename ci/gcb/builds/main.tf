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

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

# Enable services used by the integration tests.
module "services" {
  source  = "./services"
  project = var.project
}

# Wait for services to be fully active before creating resources.
# Service enablement can take time to propagate.
resource "time_sleep" "wait_for_services" {
  create_duration = "60s"

  triggers = {
    services = join(",", module.services.services)
  }

  depends_on = [module.services]
}

# Create the worker pools and other resources *hosting* the integration tests.
module "build-resources" {
  source     = "./build-resources"
  project    = var.project
  region     = var.region
  depends_on = [time_sleep.wait_for_services]
}

# Create the resources we will use in the integration tests.
module "test-resources" {
  source     = "./test-resources"
  project    = var.project
  region     = var.region
  depends_on = [time_sleep.wait_for_services]
}

# Create the service account needed for GCB and grant it the necessary
# permissions.
module "grants" {
  source      = "./grants"
  project     = var.project
  build_cache = module.build-resources.build-cache
}

# Create the GCB triggers.
module "triggers" {
  depends_on              = [module.services, module.build-resources, module.test-resources, module.grants]
  source                  = "./triggers"
  project                 = var.project
  region                  = var.region
  gcb_app_installation_id = var.gcb_app_installation_id
  gcb_secret_name         = var.gcb_secret_name
  service_account         = module.grants.runner
}
