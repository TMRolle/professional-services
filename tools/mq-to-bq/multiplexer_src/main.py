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

import json
import os
import base64
from google.cloud import pubsub_v1, asset_v1
import google.cloud.logging
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from google.cloud.asset_v1.services.asset_service.pagers import ListAssetsPager
from google.api_core.exceptions import TooManyRequests, ResourceExhausted
import re
from datetime import datetime, timedelta, timezone
import os

TARGET_PUBSUB_TOPIC = os.environ.get("TARGET_PUBSUB_TOPIC")

log_client=google.cloud.logging.Client()
log_client.setup_logging()

def rounded_mql_time(delta):
  return f"d'{(datetime.min + round((datetime.now(timezone.utc) - datetime.min)/delta) * delta).strftime('%Y/%m/%d %H:%M')}'"

def process_config(scope, queries, asset_client: asset_v1.AssetServiceClient, pubsub_client: pubsub_v1.PublisherClient, executor: ThreadPoolExecutor):
  futures={}
  req=asset_v1.ListAssetsRequest()
  req.asset_types=['compute.googleapis.com/Project']
  req.parent=scope
  req.page_size=1000
  res=asset_client.list_assets(request=req)
  for asset in res:
    project=asset.name.split('/')[-1]
    for metric_name, metric_query in queries.items():
      metric_query=re.sub('ROUNDED_HOUR', rounded_mql_time(timedelta(minutes=60)), metric_query)
      metric_query=re.sub('ROUNDED_30MIN', rounded_mql_time(timedelta(minutes=30)), metric_query)
      metric_query=re.sub('ROUNDED_15MIN', rounded_mql_time(timedelta(minutes=15)), metric_query)
      metric_query=re.sub('ROUNDED_10MIN', rounded_mql_time(timedelta(minutes=10)), metric_query)
      metric_query=re.sub('ROUNDED_5MIN', rounded_mql_time(timedelta(minutes=5)), metric_query)
      msg_str=json.dumps({
          'projects': [project],
          'queries': {metric_name: metric_query},
      })
      data=msg_str.encode('utf-8')
      futures[executor.submit(pubsub_client.publish, str(TARGET_PUBSUB_TOPIC), data)] = f"{project}:{metric_name}"
  errors=[]
  for fut in as_completed(futures):
    try:
      fut.result()
    except Exception as err:
      logging.exception(f"Failed to fanout for project {futures[fut]}: {err}")
      errors.append(err)
  if errors:
    raise RuntimeError(f"Processing failed due to errors: {errors}")
  else:
    logging.info(f"Performed fanout for {len(queries)} queries on {len(futures)/len(queries)} projects.")

def multiplex(event, context):
  """Background Cloud Function to be triggered by Pub/Sub.
  Args:
     event (dict):  The dictionary with data specific to this type of
            event. The `@type` field maps to
             `type.googleapis.com/google.pubsub.v1.PubsubMessage`.
            The `data` field maps to the PubsubMessage data
            in a base64-encoded string. The `attributes` field maps
            to the PubsubMessage attributes if any is present.
     context (google.cloud.functions.Context): Metadata of triggering event
            including `event_id` which maps to the PubsubMessage
            messageId, `timestamp` which maps to the PubsubMessage
            publishTime, `event_type` which maps to
            `google.pubsub.topic.publish`, and `resource` which is
            a dictionary that describes the service API endpoint
            pubsub.googleapis.com, the triggering topic's name, and
            the triggering event type
            `type.googleapis.com/google.pubsub.v1.PubsubMessage`.
  Returns:
    None. The output is written to Cloud Logging.
  """

  data=json.loads(base64.b64decode(event['data']).decode('utf-8'))

  job=data['job_name']
  scope=data['scope']
  metrics=data['metrics']

  logging.info(f"Running multiplexer for monitoring export job {job}")

  asset_client = asset_v1.AssetServiceClient()
  pubsub_client = pubsub_v1.PublisherClient()

  with ThreadPoolExecutor(max_workers=50) as executor:
    try:
      process_config(scope, metrics, asset_client, pubsub_client, executor)
    except Exception:
      logging.exception(f"Monitoring export job {job} encountered errors!")
      raise

