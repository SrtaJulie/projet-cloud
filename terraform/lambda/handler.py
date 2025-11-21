import json
import os
import uuid
import datetime
import decimal
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.environ.get("TABLE_NAME")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def table_exists():
    """Vérifie si la table DynamoDB existe réellement."""
    try:
        table.meta.client.describe_table(TableName=TABLE_NAME)
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceNotFoundException":
            return False
        raise e


def convert_decimals(item):
    if isinstance(item, list):
        return [convert_decimals(i) for i in item]
    if isinstance(item, dict):
        return {k: convert_decimals(v) for k, v in item.items()}
    if isinstance(item, Decimal):
        return float(item)
    return item


def make_response(status_code, body):
    body = convert_decimals(body)
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        },
        "body": json.dumps(body),
    }


def handler(event, context):
    print("EVENT:", json.dumps(event))

    # Empêche la Lambda de toucher DynamoDB si la table n'existe pas encore
    if not table_exists():
        return make_response(503, {
            "error": "Table DynamoDB non encore disponible",
            "hint": "Réessayez dans quelques secondes"
        })

    http_method = event.get("httpMethod", "GET")
    path = event.get("path", "/")


    def is_path(p):
        return path == p or path.endswith(p)

    if http_method == "OPTIONS":
        return make_response(200, {"ok": True})

    # GET /bounties
    if is_path("/bounties") and http_method == "GET":
        items = table.scan().get("Items", [])
        items = sorted(items, key=lambda x: float(x.get("reward", 0)), reverse=True)
        return make_response(200, items)

    # POST /bounty
    if is_path("/bounty") and http_method == "POST":
        try:
            body = json.loads(event.get("body") or "{}")
        except:
            return make_response(400, {"error": "JSON invalide"})

        bounty_id = "BOUNTY#" + str(uuid.uuid4())

        reward_raw = body.get("reward", 0)
        try:
            reward = Decimal(str(reward_raw))
        except:
            reward = Decimal("0")

        item = {
            "pk": bounty_id,
            "name": body.get("name", "Inconnu"),
            "description": body.get("description", ""),
            "status": body.get("status", "unknown"),
            "photoUrl": body.get("photoUrl", ""),
            "reward": reward,
            "claimed": False,
        }

        table.put_item(Item=item)
        return make_response(200, item)

    # POST /claim
    if is_path("/claim") and http_method == "POST":
        try:
            body = json.loads(event.get("body") or "{}")
        except:
            return make_response(400, {"error": "JSON invalide"})

        bounty_id = body.get("bountyId")
        if not bounty_id:
            return make_response(400, {"error": "bountyId manquant"})

        try:
            result = table.update_item(
                Key={"pk": bounty_id},
                UpdateExpression="SET claimed = :c, claimer = :n, proof = :p, claimedAt = :t",
                ExpressionAttributeValues={
                    ":c": True,
                    ":n": body.get("claimer", "Inconnu"),
                    ":p": body.get("proof", ""),
                    ":t": datetime.datetime.utcnow().isoformat() + "Z",
                },
                ReturnValues="ALL_NEW",
            )
        except Exception as e:
            print("UPDATE ERROR:", str(e))
            return make_response(500, {"error": "Erreur lors de l'update"})

        return make_response(200, result.get("Attributes", {}))

    return make_response(404, {"error": "Route inconnue", "path": path})
