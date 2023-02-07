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

project_id = "MY_EXAMPLE_PROJECT"
export_project_id = "MY_EXAMPLE_BQ_PROJECT"
query_config =  [
    {
      job_name = "basic_gce_utilization"
      description = "Example job, exports compute engine CPU usage time"
      scope = "organizations/12345678"
      schedule = "0 11 * * *"
      metrics = {
        "instance/cpu/usage_time" = <<EOT
          fetch gce_instance
        | metric 'compute.googleapis.com/instance/cpu/usage_time'
        | group_by 60m, [value_usage_time_aggregate: aggregate(value.usage_time)]
        | within 1d, ROUNDED_HOUR
        EOT

        "instance/cpu/utilization" = <<EOT
          fetch gce_instance
        | metric 'compute.googleapis.com/instance/cpu/utilization'
        | group_by 60m, [value_usage_time_aggregate: mean(value.utilization)]
        | within 1d, ROUNDED_HOUR
        EOT
      }
    },
    {
      job_name = "gke_cost_container_metrics"
      description = "Example job, exports container level cost optimization metrics"
      scope = "organizations/12345678"
      schedule = "0 12 * * *"
      metrics = {
        "kubernetes.io/container/cpu/core_usage_time" = <<EOT
          fetch k8s_container
          | metric 'kubernetes.io/container/cpu/core_usage_time'
          | align rate(1h)
          | every 1h
          | group_by
              [resource.project_id, resource.cluster_name, resource.namespace_name,
               resource.container_name,
               metadata.system.node_name: metadata.system_labels.node_name],
              [value_core_usage_time_aggregate: aggregate(value.core_usage_time)]
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/node/cpu/allocatable_cores" = <<EOT

          fetch k8s_node
          | metric 'kubernetes.io/node/cpu/allocatable_cores'
          | group_by 1h, [value_allocatable_cores_mean: mean(value.allocatable_cores)]
          | every 1h
          | within 1d, ROUNDED_HOUR

        EOT

        "kubernetes.io/container/cpu/request_cores" = <<EOT
          fetch k8s_container
          | metric 'kubernetes.io/container/cpu/request_cores'
          | group_by 1h, [value_request_cores_mean: mean(value.request_cores)]
          | every 1h
          | group_by
              [resource.project_id, resource.location, resource.cluster_name,
               resource.namespace_name, resource.container_name,
               metadata.system.node_name: metadata.system_labels.node_name],
              [value_request_cores_mean_aggregate: aggregate(value_request_cores_mean)]
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/container/cpu/limit_cores" = <<EOT
          fetch k8s_container
          | metric 'kubernetes.io/container/cpu/limit_cores'
          | group_by 1h, [value_limit_cores_mean: mean(value.limit_cores)]
          | every 1h
          | group_by
              [resource.project_id, resource.location, resource.cluster_name,
               resource.namespace_name, resource.container_name,
               metadata.system.node_name: metadata.system_labels.node_name],
              [value_limit_cores_mean_aggregate: aggregate(value_limit_cores_mean)]
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/container/cpu/request_utilization" = <<EOT
          fetch k8s_container
          | metric 'kubernetes.io/container/cpu/request_utilization'
          | group_by 1h, [value_request_utilization_mean: mean(value.request_utilization)]
          | every 1h
          | group_by
              [resource.project_id, resource.location, resource.cluster_name,
               resource.namespace_name, resource.container_name,
               metadata.system.node_name: metadata.system_labels.node_name],
              [value_request_utilization_mean_aggregate: aggregate(value_request_utilization_mean)]
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/node/cpu/total_cores" = <<EOT
          fetch k8s_node
          | metric 'kubernetes.io/node/cpu/total_cores'
          | group_by 1h, [value_total_cores_mean: mean(value.total_cores)]
          | every 1h
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/node/cpu/allocatable_utilization" = <<EOT
          fetch k8s_node
          | metric 'kubernetes.io/node/cpu/allocatable_utilization'
          | group_by 1h,
              [value_allocatable_utilization_mean: mean(value.allocatable_utilization)]
          | every 1h
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/container/memory/used_bytes" = <<EOT

        fetch k8s_container
        | metric 'kubernetes.io/container/memory/used_bytes'
        | group_by 1h, [value_used_bytes_mean: mean(value.used_bytes)]
        | every 1h
        | group_by
            [resource.project_id, resource.location, resource.cluster_name,
             resource.namespace_name, resource.container_name,
             metadata.system.node_name: metadata.system_labels.node_name],
            [value_used_bytes_mean_aggregate: aggregate(value_used_bytes_mean)]
        | within 1d, ROUNDED_HOUR

        EOT

        "kubernetes.io/container/memory/request_bytes" = <<EOT
          fetch k8s_container
          | metric 'kubernetes.io/container/memory/request_bytes'
          | group_by 1h, [value_request_bytes_mean: mean(value.request_bytes)]
          | every 1h
          | group_by
              [resource.project_id, resource.location, resource.cluster_name,
               resource.namespace_name, resource.container_name,
               metadata.system.node_name: metadata.system_labels.node_name],
              [value_request_bytes_mean_aggregate: aggregate(value_request_bytes_mean)]
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/container/memory/limit_bytes" = <<EOT
          fetch k8s_container
          | metric 'kubernetes.io/container/memory/limit_bytes'
          | group_by 1h, [value_limit_bytes_mean: mean(value.limit_bytes)]
          | every 1h
          | group_by
              [resource.project_id, resource.location, resource.cluster_name,
               resource.namespace_name, resource.container_name,
               metadata.system.node_name: metadata.system_labels.node_name],
              [value_limit_bytes_mean_aggregate: aggregate(value_limit_bytes_mean)]
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/node/memory/used_bytes" = <<EOT
          fetch k8s_node
          | metric 'kubernetes.io/node/memory/used_bytes'
          | group_by 1h, [value_used_bytes_mean: mean(value.used_bytes)]
          | every 1h
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/node/memory/allocatable_bytes" = <<EOT
          fetch k8s_node
          | metric 'kubernetes.io/node/memory/allocatable_bytes'
          | group_by 1h, [value_allocatable_bytes_mean: mean(value.allocatable_bytes)]
          | every 1h
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/node/memory/total_bytes" = <<EOT
          fetch k8s_node
          | metric 'kubernetes.io/node/memory/total_bytes'
          | group_by 1h, [value_total_bytes_mean: mean(value.total_bytes)]
          | every 1h
          | within 1d, ROUNDED_HOUR
        EOT

        "kubernetes.io/node/memory/allocatable_utilization" = <<EOT
          fetch k8s_node
          | metric 'kubernetes.io/node/memory/allocatable_utilization'
          | group_by 1h,
              [value_allocatable_utilization_mean: mean(value.allocatable_utilization)]
          | every 1h
          | within 1d, ROUNDED_HOUR
        EOT

      },
    },
  ]

/* Template for daily export job
 
    {
      job_name = "JOB_NAME"
      description = ""
      scope = "SCOPE"
      schedule = "0 10 * * *"
      metrics = {
        "METRIC_NAME" = <<EOT

        [MQL QUERY GOES HERE]

        EOT

        "METRIC_NAME_2" = <<EOT

        [MQL QUERY GOES HERE]

        EOT
      },
*/
