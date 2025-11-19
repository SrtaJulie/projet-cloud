import json
import uuid
import boto3
import os

LOCALSTACK = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")

dynamodb = boto3.resource(
    "dynamodb",
    region_name="eu-west-1",
    endpoint_url=f"http://{LOCALSTACK}:4566"
)

table = dynamodb.Table(os.environ["TABLE_NAME"])

def handler(event, context):
    path = event.get("path", "").rstrip("/")
    method = event.get("httpMethod", "")

    # /hello
    if path == "/hello" and method == "GET":
        return respond(200, {"message": "Ahoy, pirate !"})

    # GET /bounties
    if path == "/bounties" and method == "GET":
        resp = table.scan()
        return respond(200, resp.get("Items", []))

    # POST /bounty
    if path == "/bounty" and method == "POST":
        body = json.loads(event["body"])
        item = {
            "pk": f"BOUNTY#{uuid.uuid4()}",
            "title": body.get("title"),
            "description": body.get("description")
        }
        table.put_item(Item=item)
        return respond(200, item)

    # POST /claim
    if path == "/claim" and method == "POST":
        body = json.loads(event["body"])
        item = {
            "pk": f"CLAIM#{uuid.uuid4()}",
            "bountyId": body.get("bountyId"),
            "claimer": body.get("claimer"),
            "proof": body.get("proof")
        }
        table.put_item(Item=item)
        return respond(200, item)

    return respond(404, {"error": "Route inconnue"})

def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }
