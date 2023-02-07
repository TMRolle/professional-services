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

resource "google_project_service" "appengine_service" {
  project = var.project_id
  service = "appengine.googleapis.com"
}

resource "google_project_service" "asset_service" {
  project = var.project_id
  service = "cloudasset.googleapis.com"
}

resource "google_project_service" "cloudscheduler_service" {
  project = var.project_id
  service = "cloudscheduler.googleapis.com"
}

resource "google_project_service" "cloudfunctions_service" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"
}

resource "google_project_service" "cloudresourcemanager_service" {
  project = var.project_id
  service = "cloudresourcemanager.googleapis.com"
}

resource "google_project_service" "compute_service" {
  project = var.project_id
  service = "compute.googleapis.com"
}

resource "google_project_service" "bigquery_service" {
  project = var.project_id
  service = "bigquery.googleapis.com"
}

resource "google_project_service" "cloudbuild_service" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"
}

resource "google_project_service" "monitoring_service" {
  project = var.project_id
  service = "monitoring.googleapis.com"
}

module "new_metrics_dataset" {
  source = "terraform-google-modules/bigquery/google"
  version = "~>5.4"
  dataset_id = "monitoring_metric_export"
  dataset_name = "monitoring_metric_export"
  project_id = var.export_project_id
  location = "US"
}

resource "google_service_account" "mql_export_metrics" {
  account_id = "mql-export-metrics"
  display_name = "MQL export metrics SA"
  project = var.project_id
}

resource "google_project_iam_member" "sa_iam_compute_viewer" {
  project = var.project_id
  role = "roles/compute.viewer"
  member = "serviceAccount:${google_service_account.mql_export_metrics.email}"
}

resource "google_project_iam_member" "sa_iam_monitoring_viewer_2" {
  project = var.project_id
  role = "roles/monitoring.viewer"
  member = "serviceAccount:${google_service_account.mql_export_metrics.email}"
}
  
resource "google_project_iam_member" "sa_iam_bq_editor" {
  project = var.project_id
  role = "roles/bigquery.dataEditor"
  member = "serviceAccount:${google_service_account.mql_export_metrics.email}"
}
  
resource "google_project_iam_member" "sa_iam_bq_jobuser" {
  project = var.project_id
  role = "roles/bigquery.jobUser"
  member = "serviceAccount:${google_service_account.mql_export_metrics.email}"
}
  
resource "google_project_iam_member" "sa_iam_pubsub_publisher" {
  project = var.project_id
  role = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.mql_export_metrics.email}"
}
  
resource "google_pubsub_topic" "mql_metric_export_topic" {
  name = "mql_metric_export"
  project = var.project_id
}

resource "google_pubsub_topic" "multiplexer_topic" {
  name = "mql_multiplexer_topic"
  project = var.project_id
}

resource "google_storage_bucket" "export_cf_src_bucket" {
  name = "${var.project_id}-metrics-cf-src"
  location = "US"
  force_destroy = true
  uniform_bucket_level_access = true
  project = var.project_id
}

data "archive_file" "cf_source_zip" {
  type = "zip"
  output_path = "${path.module}/cf_source.zip"
  source_dir = "${path.module}/export_src"
}

resource "google_storage_bucket_object" "export_cf_src_zip_object" {
  name = "cf_source.zip"
  source = data.archive_file.cf_source_zip.output_path
  bucket = google_storage_bucket.export_cf_src_bucket.name
  depends_on = [
    google_storage_bucket.export_cf_src_bucket,
    data.archive_file.cf_source_zip
  ]
}

resource "google_cloudfunctions_function" "export_function" {
  name = "mql_export_metrics"
  description = "Cloud function to export stackdriver metrics to bigquery"
  runtime = "python38"
  available_memory_mb = 1024
  timeout = 540
  max_instances = var.max_export_workers
  region = var.location_id
  source_archive_bucket = google_storage_bucket.export_cf_src_bucket.name
  source_archive_object = google_storage_bucket_object.export_cf_src_zip_object.name
  project = var.project_id
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource = google_pubsub_topic.mql_metric_export_topic.id
    failure_policy {
      retry=false
    }
  }
  environment_variables = {
    PROJECT_ID = var.export_project_id
    BIGQUERY_DATASET = module.new_metrics_dataset.bigquery_dataset.dataset_id
  }
  entry_point = "export_metric_data"
  service_account_email = google_service_account.mql_export_metrics.email
  depends_on = [
    module.new_metrics_dataset,
    google_storage_bucket_object.export_cf_src_zip_object,
  ]
  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.export_cf_src_zip_object,
    ]
  }
}

data "archive_file" "mp_source_zip" {
  type = "zip"
  output_path = "${path.module}/mp_source.zip"
  source_dir = "${path.module}/multiplexer_src"
}

resource "google_storage_bucket_object" "export_mp_src_zip_object" {
  name = "mp_source.zip"
  source = data.archive_file.mp_source_zip.output_path
  bucket = google_storage_bucket.export_cf_src_bucket.name
  depends_on = [
    google_storage_bucket.export_cf_src_bucket,
    data.archive_file.mp_source_zip
  ]
  detect_md5hash = true
}

resource "google_cloudfunctions_function" "multiplexer_function" {
  name = "mq_to_bq_multiplexer"
  description = "Cloud function to orchestrate metrics exports across a folder or organization"
  runtime = "python38"
  available_memory_mb = 4096
  timeout = 300
  max_instances = 1
  region = var.location_id
  source_archive_bucket = google_storage_bucket.export_cf_src_bucket.name
  source_archive_object = google_storage_bucket_object.export_mp_src_zip_object.name
  project = var.project_id
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource = google_pubsub_topic.multiplexer_topic.id 
  }
  environment_variables = {
    TARGET_PUBSUB_TOPIC = google_pubsub_topic.mql_metric_export_topic.id
  }
  entry_point = "multiplex"
  service_account_email = google_service_account.mql_export_metrics.email
  depends_on = [
    module.new_metrics_dataset,
    google_storage_bucket_object.export_mp_src_zip_object,
  ]
  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.export_mp_src_zip_object,
    ]
  }
}

resource "google_cloud_scheduler_job" "cron_job" {
  for_each = {for index, cfg in var.query_config: cfg.job_name => cfg}
  name = "mq_export_${each.value.job_name}"
  description = each.value.description
  schedule = each.value.schedule
  project = var.project_id
  region = var.location_id
  
  pubsub_target  {
    topic_name = google_pubsub_topic.multiplexer_topic.id
    data = base64encode(jsonencode({
      job_name = each.key
      scope = each.value.scope
      metrics = each.value.metrics
    }))
  }
}
 


