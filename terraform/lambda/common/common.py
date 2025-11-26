import json
import os
import datetime
from decimal import Decimal
import boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.environ.get("TABLE_NAME")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def table_exists():
    """Vérifie si la table existe."""
    try:
        table.meta.client.describe_table(TableName=TABLE_NAME)
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceNotFoundException":
            return False
        raise e


def convert_decimals(value):
    if isinstance(value, list):
        return [convert_decimals(v) for v in value]
    if isinstance(value, dict):
        return {k: convert_decimals(v) for k, v in value.items()}
    if isinstance(value, Decimal):
        return float(value)
    return value


def response(status, body):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        },
        "body": json.dumps(convert_decimals(body)),
    }
