# Copyright 2023 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "project_id" {
  description = "The project to set up the exporter in. Recommended to use a dedicated project for this."
  type = string
}

variable "export_project_id" {
  description = "The project to export results to. Can be the same project or an external one. If an external project is used, make sure to grant the necessary IAM roles on that project to allow the service account to create and upload data to bigquery."
  type = string
}

variable "location_id" {
  description = "The location to serve the cloud function from."
  type = string
  default = "us-central1"
}

variable "retention_days" {
  description = "Days to retain monitoring data in BQ"
  type = number
  default = 30
}

variable "max_export_workers" {
  description = "Maximum number of Cloud Functions workers to run in parallel for the export job"
  type = number
  default = 50
}

variable "query_config" {
  description = "Query configuration. See default value for schema."
  type = list(
    object(
      {
        job_name = string
        description = string
        scope = string
        schedule = string
        metrics = map(string)
      }
    )
  )
  default = [
    {
      job_name = "example_gce_metrics"
      description = "Example job, exports compute engine CPU usage time"
      scope = "organizations/12345678"
      schedule = "0 0 * * *"
      metrics = {
        "instance/cpu/usage_time" = <<EOT
          fetch gce_instance
        | metric 'compute.googleapis.com/instance/cpu/usage_time'
        | group_by 60m, [value_usage_time_aggregate: aggregate(value.usage_time)]
        | within 1d, ROUNDED_HOUR 
        EOT 
      }
    }
  ]
}
