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
  default = "swift-sdk-testing"
}

variable "region" {
  default = "us-central1"
}

variable "zone" {
  default = "us-central1-f"
}

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
variable "gcb_app_installation_id" {
  default = 1168573
}

# Google Cloud uses Secret Manager to save the Github access token. Similar to
# the previous problem. It is much easier to use the UI to create the
# connection and just record it here.
variable "gcb_secret_name" {
  default = "projects/swift-sdk-testing/secrets/GitHub-github-oauthtoken-a264d3/versions/latest"
}
