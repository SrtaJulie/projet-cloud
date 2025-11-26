import json
import datetime
from common.common import table, table_exists, response

def handler(event, context):
    if not table_exists():
        return response(503, {"error": "Table pas prête"})

    try:
        body = json.loads(event.get("body") or "{}")
    except:
        return response(400, {"error": "JSON invalide"})

    bounty_id = body.get("bountyId")
    if not bounty_id:
        return response(400, {"error": "bountyId manquant"})

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
        return response(500, {"error": str(e)})

    return response(200, result.get("Attributes", {}))