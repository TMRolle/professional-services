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

import logging
import json

import config
from concurrent.futures import ThreadPoolExecutor, as_completed
from google.cloud import bigquery
import google.cloud.logging
from google.cloud import monitoring_v3
import base64
from google.api.label_pb2 import _LABELDESCRIPTOR_VALUETYPE
from google.api.metric_pb2 import _METRICDESCRIPTOR_VALUETYPE, _METRICDESCRIPTOR_METRICKIND
from google.api_core.retry import Retry
from google.api_core.exceptions import AlreadyExists, TooManyRequests, ResourceExhausted, InternalServerError, BadGateway, ServiceUnavailable, Conflict, NotFound
import re

log_client = google.cloud.logging.Client()
log_client.setup_logging()

_MONITORING_RETRIABLE_TYPES = (
    TooManyRequests,
    InternalServerError,
    BadGateway,
    ServiceUnavailable,
    ResourceExhausted,
)


def is_monitoring_retryable(exc):
    return isinstance(exc, _MONITORING_RETRIABLE_TYPES)


def build_bq_schema_from_descriptor(
        descriptor: monitoring_v3.TimeSeriesDescriptor):
    schema = [
        bigquery.SchemaField("start_time", "TIMESTAMP"),
        bigquery.SchemaField("end_time", "TIMESTAMP", mode="REQUIRED"),
    ]
    for label in descriptor.label_descriptors:
        label_value_type = _LABELDESCRIPTOR_VALUETYPE.values_by_number[
            label.value_type].name
        key = re.sub('[^a-zA-Z0-9_]', '_', label.key)
        schema.append(
            bigquery.SchemaField(key,
                                 label_value_type,
                                 description=label.description))
    for point in descriptor.point_descriptors:
        kind = _METRICDESCRIPTOR_METRICKIND.values_by_number[
            point.metric_kind].name
        point_type = _METRICDESCRIPTOR_VALUETYPE.values_by_number[
            point.value_type].name
        point_key = re.sub('[^a-zA-Z0-9_]', '_', point.key)
        if point_type == "DOUBLE":
            point_type = "FLOAT"
        schema.append(
            bigquery.SchemaField(point_key,
                                 point_type,
                                 description=f"{kind} metric, {point.unit}"))
    return schema


def check_if_exists(table_id, client):
    try:
        client.get_table(table_id)
        return True
    except NotFound:
        return False


def create_bq_table(export_project, dataset, table_name, schema,
                    client: bigquery.Client):
    table_id = f"{export_project}.{dataset}.{table_name}"
    table = bigquery.Table(table_id, schema=schema)
    table.time_partitioning = bigquery.TimePartitioning(
        type_="DAY", expiration_ms=(1000 * 60 * 60 * 24 * 90), field='end_time')
    try:
        t = client.create_table(table)
        logging.info("Created table {}.{}.{}".format(t.project, t.dataset_id,
                                                     t.table_id))
    except (AlreadyExists, Conflict):
        logging.debug("Table {}.{}.{} already exists".format(
            table.project, table.dataset_id, table.table_id))
    return bigquery.Table(table_id, schema=schema)


def new_export_metric(export_project, dataset, table, query, project,
                      client: monitoring_v3.QueryServiceClient,
                      bq_client: bigquery.Client):
    retry_policy = Retry(predicate=is_monitoring_retryable)
    req = monitoring_v3.QueryTimeSeriesRequest()
    req.name = f'projects/{project}'
    req.query = query
    pager = client.query_time_series(request=req, retry=retry_policy)
    if not pager.time_series_data:
        logging.debug(f"No data for project {project}")
        return 0
    total_rows = 0
    descriptor = pager.time_series_descriptor
    schema = build_bq_schema_from_descriptor(descriptor)
    table_id = f"{export_project}.{dataset}.{table}"
    table_obj = bigquery.Table(table_id, schema=schema)
    if not check_if_exists(table_id, bq_client):
        table_obj = create_bq_table(export_project, dataset, table, schema,
                                    bq_client)

    for data in pager:
        entry = {}
        rows = []
        for label_val, label_descript in zip(data.label_values,
                                             descriptor.label_descriptors):
            val_type = _LABELDESCRIPTOR_VALUETYPE.values_by_number[
                label_descript.value_type].name
            key = re.sub('[^a-zA-Z0-9_]', '_', label_descript.key)
            if val_type == "STRING":
                entry[key] = label_val.string_value
            elif val_type == "BOOL":
                entry[key] = label_val.bool_value
            elif val_type == "INT64":
                entry[key] = label_val.int64_value
        for point in data.point_data:
            row = entry.copy()
            row['start_time'] = point.time_interval.start_time
            row['end_time'] = point.time_interval.end_time
            for col_value, col_descript in zip(point.values,
                                               descriptor.point_descriptors):
                col_type = _METRICDESCRIPTOR_VALUETYPE.values_by_number[
                    col_descript.value_type].name
                point_key = re.sub('[^a-zA-Z0-9_]', '_', col_descript.key)
                if col_type == "DOUBLE":
                    row[point_key] = col_value.double_value
                elif col_type == "INT64":
                    row[point_key] = col_value.int64_value
                elif col_type == "BOOL":
                    row[point_key] = col_value.bool_value
                elif col_type == "STRING":
                    row[point_key] = col_value.string_value
            rows.append(row)
        bq_client.insert_rows(table=table_obj, rows=rows)
        total_rows += len(rows)
    for err in pager.partial_errors:
        logging.error(f"Partial error in getting metrics for {project}: {err}")
    return total_rows


def export_metric_data(event, context):
    """Background Cloud Function to be triggered by Pub/Sub.
  Args:
     event (dict):  The dictionary with data specific to this type of
     event. The `data` field contains the PubsubMessage message. The
     `attributes` field will contain custom attributes if there are any.
     context (google.cloud.functions.Context): The Cloud Functions event
     metadata. The `event_id` field contains the Pub/Sub message ID. The
     `timestamp` field contains the publish time.
  """
    queries = []
    projects = []

    if 'data' in event:
        data = json.loads(base64.b64decode(event['data']).decode('utf-8'))
        if 'projects' in data:
            projects = data['projects']
        if 'queries' in data:
            queries = data['queries']
    with ThreadPoolExecutor(max_workers=10) as executor:
        failures = []
        monitoring_client = monitoring_v3.QueryServiceClient()
        bq_client = bigquery.Client()
        futures = []
        for project in projects:
            total_rows = 0
            for metric, query in queries.items():
                metric_table_name = re.sub('[^a-zA-Z0-9_]', '_', metric)
                futures.append(
                    executor.submit(new_export_metric, config.PROJECT_ID,
                                    config.BIGQUERY_DATASET, metric_table_name,
                                    query, project, monitoring_client,
                                    bq_client))
            for fut in as_completed(futures):
                try:
                    total_rows += fut.result()
                except Exception as err:
                    failures.append(err)
            logging.info(
                f"Finished exporting {total_rows} data points for project {project}"
            )
            if failures:
                logging.error(
                    f"Failures occured while processing {len(failures)}/{len(queries)*len(projects)} queries!"
                )
                raise RuntimeError(str(failures))
