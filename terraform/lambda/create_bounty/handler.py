import json
import uuid
from decimal import Decimal
from common.common import table, table_exists, response

def handler(event, context):
    if not table_exists():
        return response(503, {"error": "Table pas prête"})

    try:
        body = json.loads(event.get("body") or "{}")
    except:
        return response(400, {"error": "JSON invalide"})

    bounty_id = "BOUNTY#" + str(uuid.uuid4())

    try:
        reward = Decimal(str(body.get("reward", 0)))
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
    return response(200, item)