# Cloud Monitoring BigQuery Exporter

## Instructions

## Architecture

![Architecture Diagram]('/arch_diagram.svg')

This module sets up a few key components in order to export Cloud Monitoring
metrics across an org/folder/project.

### Cloud Scheduler

Individual cloud scheduler jobs are set up for each export job configured in the
terraform config. This allows for the service to be used to set up various
exports with their own export schedules, granularity, scope of projects, etc.
These cloud scheduler tasks send messages to a pubsub topic to trigger the
Multiplexer microservice.

### Cloud Functions - Multiplexer

This microservice is an event-driven function that handles sharding out query
jobs for an organization or folder into individual export jobs for each project
and query, traversing the folder layout through the Cloud Asset API.
This is necessary to allow for horizontal scaling for large numbers of projects.
It also handles replacing the supported `ROUNDED` macros with the appropriate
MQL timestamps.
It publishes individual export jobs to a pubsub topic in order to trigger the
exporter service.

## Cloud Functions - Exporter

This microservice is an event-driven function that pulls monitoring data for a
given set of queries on a specific project, and uploads the data to the
centralized BQ dataset. It additionally supports the macros `ROUNDED_HOUR`,
`ROUNDED_30MIN`, `ROUNDED_15MIN`, `ROUNDED_10MIN`, and `ROUNDED_5MIN`,
which will be substituted for the appropriate MQL formatted timestamp rounded to
the given boundary. This is to allow for cleaner and more convenient aggregation,
especially for long-running export jobs.

The exporter outputs the results from the queries into a dataset in the project 
specified by the `export_project_id` variable, named `monitoring_metric_export`.
Each metric is output to its own dedicated table, which will be created if it
doesn't already exist. Output tables are metric-specific but shared between all 
projects. Each output table has a generated schema based on the labels and point
values specified in the relevant metric descriptor.

## Limitations

This exporter does not support `DISTRIBUTION` metrics at this time.
