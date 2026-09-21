import azure.functions as func
from azure.data.tables import TableServiceClient
import requests
import datetime
import os
import logging


def main(mytimer: func.TimerRequest) -> None:
    target_url = os.environ["TARGET_URL"]
    storage_conn = os.environ["AzureWebJobsStorage"]

    check_time = datetime.datetime.utcnow()
    result_status = "PASS"
    error_detail = None
    response_ms = None

    try:
        response = requests.get(target_url, timeout=10)
        response_ms = response.elapsed.total_seconds() * 1000

        if response.status_code != 200:
            result_status = "FAIL"
            error_detail = f"HTTP {response.status_code}"
        elif response_ms > 5000:
            result_status = "SLOW"
            error_detail = f"Response time {response_ms:.0f}ms exceeded 5000ms"
        elif "error" in response.text.lower() and "404" in response.text:
            result_status = "FAIL"
            error_detail = "Page contains error indicators"

    except requests.exceptions.ConnectionError:
        result_status = "FAIL"
        error_detail = "Connection refused — server unreachable"
    except requests.exceptions.Timeout:
        result_status = "FAIL"
        error_detail = "Request timed out after 10 seconds"
    except Exception as e:
        result_status = "FAIL"
        error_detail = str(e)

    # PartitionKey restrictions: Azure Table Storage forbids / : # ? in
    # PartitionKey or RowKey. The target URL contains / and :, which would
    # cause silent write failures — so PartitionKey is hardcoded to "uptime"
    # instead, with the real URL stored in a separate TargetUrl column.
    #
    # create_table_if_not_exists() lives on TableServiceClient, not
    # TableClient — calling it on the wrong object raises AttributeError.
    table_service = TableServiceClient.from_connection_string(storage_conn)
    table_service.create_table_if_not_exists("uptimechecks")
    table_client = table_service.get_table_client("uptimechecks")

    entity = {
        "PartitionKey": "uptime",
        "RowKey": check_time.strftime("%Y%m%d%H%M%S"),
        "Timestamp": check_time.isoformat(),
        "Status": result_status,
        "ResponseMs": int(response_ms) if response_ms else 0,
        "ErrorDetail": error_detail or "",
        "TargetUrl": target_url,
    }

    try:
        table_client.upsert_entity(entity)
        logging.info(f"Check: {result_status} | {response_ms:.0f}ms | {target_url}" if response_ms else f"Check: {result_status} | {target_url}")
    except Exception as e:
        logging.error(f"Failed to write result to table: {e}")

    if result_status != "PASS":
        logging.error(f"SITE DOWN: {target_url} | {result_status} | {error_detail}")
