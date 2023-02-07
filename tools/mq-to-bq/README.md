# Cloud Monitoring BigQuery Exporter

## Instructions

## Architecture

This module sets up a few key components in order to export Cloud Monitoring
metrics across an org/folder/project to a single centralized BigQuery table.

### Cloud Scheduler

Individual cloud scheduler jobs are set up for each export job configured in the
terraform config. This allows for the service to be used to set up various
exports with their own export schedules, granularity, scope of projects, etc.
These cloud scheduler tasks send messages to a pubsub topic to trigger the
Multiplexer microservice.

### Cloud Functions - Multiplexer

This microservice is an event-driven function that handles sharding out query
jobs for an organization or folder into individual project-level export jobs,
traversing the folder layout through the Cloud Asset API.
This is necessary to allow for horizontal scaling for large numbers of projects.
It publishes individual project export jobs to a pubsub topic to trigger the
exporter service.

## Cloud Functions - Exporter

This microservice is an event-driven function that pulls monitoring data for a
given set of queries on a specific project, and uploads the data to the
centralized BQ table. It additionally supports a ROUNDED_HOUR value in the
provided MQL queries, which it will substitute with the nearest hour
boundary. This is to allow for cleaner and more convenient aggregation,
especially for long-running export jobs.
