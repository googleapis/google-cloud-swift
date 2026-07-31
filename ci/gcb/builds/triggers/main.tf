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
variable "region" {}
variable "service_account" {}

locals {
  # Google Cloud Build installs an application on the GitHub organization or
  # repository. This id is hard-coded here because there is no easy way [^1] to
  # manage that installation via terraform.
  #
  # [^1]: there is a way, described in [Connecting a Gitub host programmatically]
  #     but I would not call that "easy". It requires (for example) manually
  #     creating a personally access token (PAT) on GitHub, and storing that
  #     in the Terraform file.
  # [Connecting a Gitub host programmatically]: https://cloud.google.com/build/docs/automating-builds/github/connect-repo-github?generation=2nd-gen#terraform
  #
  gcb_app_installation_id = 1168573

  # Google Cloud uses Secret Manager to save the Github access token. Similar to
  # the previous problem. It is much easier to use the UI to create the
  # connection and just record it here.
  gcb_secret_name = "projects/${var.project}/secrets/GitHub-github-oauthtoken-a264d3/versions/latest"

  # These builds appear in both the PR (Pull Request) triggers and the
  # PM (Post Merge) triggers. See below for builds that only appear in one.
  common_builds = {
#    unit-tests = {
#      config = "scripted.yaml"
#      script = "unit-tests"
#    }
#    minimum-swift = {
#      config = "minimum-swift.yaml"
#      script = "unit-tests"
#    }
  }

  # These are builds that only run during Pull Requests.
  pr_build_overrides = {}

  # There are builds that only run Post Merge.
  pm_build_overrides = {}

  # Compute the effective list of builds.
  pr_builds = merge(local.common_builds, local.pr_build_overrides)
  pm_builds = merge(local.common_builds, local.pm_build_overrides)
}

# This is used to retrieve the project number. The project number is embedded in
# certain P4 (Per-product per-project) service accounts.
data "google_project" "project" {
}

# This service account is created externally. It is used for the terraform build.
data "google_service_account" "terraform-runner" {
  account_id = "terraform-runner"
}

resource "google_cloudbuildv2_connection" "github" {
  project  = var.project
  location = var.region
  name     = "github"

  github_config {
    app_installation_id = local.gcb_app_installation_id
    authorizer_credential {
      oauth_token_secret_version = local.gcb_secret_name
    }
  }
}

resource "google_cloudbuildv2_repository" "main" {
  project           = var.project
  location          = var.region
  name              = "googleapis-google-cloud-swift"
  parent_connection = google_cloudbuildv2_connection.github.name
  remote_uri        = "https://github.com/googleapis/google-cloud-swift.git"
}

resource "google_cloudbuild_trigger" "pull-request" {
  for_each = tomap(local.pr_builds)
  location = var.region
  name     = "gcb-pr-${each.key}"
  filename = ".gcb/${each.value.config}"
  tags     = ["pull-request", "name:${each.key}"]

  service_account = var.service_account

  repository_event_config {
    repository = google_cloudbuildv2_repository.main.id
    pull_request {
      branch          = "^(main)$"
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }

  substitutions = {
    _SCRIPT = lookup(each.value, "script", "")
  }
}

resource "google_cloudbuild_trigger" "post-merge" {
  for_each = {
    # `tomap` will not do because we need to normalize these as objects.
    for k, v in local.pm_builds : k => {
      config         = v.config,
      script         = try(v.script, "")
      flags          = try(v.flags, "")
      swift_version  = try(v.swift_version, null)
      included_files = try(v.included_files, [])
    }
  }
  location       = var.region
  name           = "gcb-pm-${each.key}"
  filename       = ".gcb/${each.value.config}"
  tags           = ["post-merge", "push", "name:${each.key}"]
  included_files = each.value.included_files

  service_account = var.service_account

  repository_event_config {
    repository = google_cloudbuildv2_repository.main.id
    push {
      branch = "^(main)$"
    }
  }

  substitutions = {
    _SCRIPT        = lookup(each.value, "script", "")
    _SWIFT_VERSION = lookup(each.value, "swift_version", null)
  }
}

resource "google_pubsub_topic" "terraform_runner_topic" {
  name = "terraform-runner"
}

resource "google_pubsub_subscription" "terraform_runner_sub" {
  name  = "terraform-sub"
  topic = google_pubsub_topic.terraform_runner_topic.name
}

resource "google_cloud_scheduler_job" "job" {
  name        = "terraform-job"
  description = "Periodically sync terraform build"
  schedule    = "0 0 * * 0" # Once a week at midnight on Sunday.

  pubsub_target {
    topic_name = google_pubsub_topic.terraform_runner_topic.id
    data       = base64encode("sync")
  }
}

resource "google_cloudbuild_trigger" "pubsub-trigger" {
  location = var.region
  name     = "gcb-pubsub-terraform"
  filename = ".gcb/terraform.yaml"
  tags     = ["scheduler", "name:terraform"]

  service_account = data.google_service_account.terraform-runner.id

  pubsub_config {
    topic = google_pubsub_topic.terraform_runner_topic.id
  }

  source_to_build {
    repository = google_cloudbuildv2_repository.main.id
    ref        = "refs/heads/main"
    repo_type  = "GITHUB"
  }
}
