import json
import os
import decimal
import boto3

from decimal import Decimal

TABLE_NAME = os.environ["TABLE_NAME"]
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def decimal_default(obj):
    if isinstance(obj, decimal.Decimal):
        return float(obj)
    raise TypeError


def make_response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        },
        "body": json.dumps(body, default=decimal_default),
    }


def handler(event, context):
    print("Event list_bounties:", json.dumps(event))

    res = table.scan()
    items = res.get("Items", [])

    # Tri décroissant sur reward (Decimal → cast en float pour trier)
    items.sort(
        key=lambda item: float(item.get("reward", Decimal(0)) or 0.0),
        reverse=True,
    )

    return make_response(200, items)