import json
import os
import decimal
import datetime
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
    print("Event claim_bounty:", json.dumps(event))

    if event.get("httpMethod") == "OPTIONS":
        return make_response(200, {"ok": True})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return make_response(400, {"error": "JSON invalide"})

    bounty_id = body.get("bountyId")
    if not bounty_id:
        return make_response(400, {"error": "bountyId manquant"})

    claimer = body.get("claimer", "Pirate inconnu")
    proof = body.get("proof", "")

    now = datetime.datetime.utcnow().isoformat() + "Z"

    try:
        result = table.update_item(
            Key={"pk": bounty_id},
            UpdateExpression=(
                "SET claimed = :c, "
                "claimer = :n, "
                "proof = :p, "
                "claimedAt = :t"
            ),
            ExpressionAttributeValues={
                ":c": True,
                ":n": claimer,
                ":p": proof,
                ":t": now,
            },
            ReturnValues="ALL_NEW",
        )
    except Exception as e:
        print("Erreur update_item:", e)
        return make_response(500, {"error": "Erreur lors de la revendication"})

    updated = result.get("Attributes", {})
    return make_response(200, updated)
