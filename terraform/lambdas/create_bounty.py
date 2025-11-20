import json
import os
import uuid
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
    print("Event create_bounty:", json.dumps(event))

    if event.get("httpMethod") == "OPTIONS":
        return make_response(200, {"ok": True})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return make_response(400, {"error": "JSON invalide"})

    bounty_id = "BOUNTY#" + str(uuid.uuid4())

    name = body.get("name") or body.get("title") or "Inconnu"
    description = body.get("description", "")
    status = body.get("status", "unknown")
    photo_url = body.get("photoUrl", "")

    reward_raw = body.get("reward", "0")

    # Toujours passer par Decimal pour DynamoDB
    try:
        reward = Decimal(str(reward_raw))
    except Exception:
        reward = Decimal("0")

    item = {
        "pk": bounty_id,
        "name": name,
        "description": description,
        "status": status,
        "photoUrl": photo_url,
        "reward": reward,
        "claimed": False,
    }

    table.put_item(Item=item)

    return make_response(201, item)
