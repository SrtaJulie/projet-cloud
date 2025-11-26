from common.common import table, table_exists, response

def handler(event, context):
    if not table_exists():
        return response(503, {"error": "Table pas prête"})

    items = table.scan().get("Items", [])
    items = sorted(items, key=lambda x: float(x.get("reward", 0)), reverse=True)

    return response(200, items)