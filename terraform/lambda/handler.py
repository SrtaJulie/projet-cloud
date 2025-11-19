import json
import boto3
import uuid
import os

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

def response(status, body):
    return {
        "statusCode": status,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
        },
        "body": json.dumps(body)
    }

def handler(event, context):
    path = event.get("path", "")
    method = event.get("httpMethod", "")

    # GET /hello
    if path.endswith("/hello") and method == "GET":
        return response(200, {"message": "Ahoy, pirate !"})

    # GET /bounties
    if path.endswith("/bounties") and method == "GET":
        items = table.scan().get("Items", [])
        return response(200, items)

    # POST /bounty
    if path.endswith("/bounty") and method == "POST":
        body = json.loads(event["body"])
        pk = f"BOUNTY#{str(uuid.uuid4())}"
        item = {
            "pk": pk,
            "title": body["title"],
            "description": body["description"]
        }
        table.put_item(Item=item)
        return response(200, item)

    # POST /claim
    if path.endswith("/claim") and method == "POST":
        body = json.loads(event["body"])
        return response(200, {"status": "claim received", "data": body})

    return response(404, {"error": "Not found"})
