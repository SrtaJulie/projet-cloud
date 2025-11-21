## CHOIX LAMBDA

# Contexte

Dans le cadre du TP Cloud, plusieurs architectures Lambda sont possibles :

- Une seule Lambda gérant toutes les routes (pattern “monolithique mais simple”)
- Plusieurs Lambdas spécialisées : list_bounties, create_bounty, claim_bounty, hello

L’architecture multi-Lambda est plus modulaire sur AWS réel, mais pas dans LocalStack, qui est le contexte de notre TP.

Ce README explique pourquoi le choix final est une seule Lambda, même si le code a été préparé pour le multi-Lambda.

# 1. Limitation technique de LocalStack sur Windows

LocalStack peut exécuter des Lambdas de deux manières :

- Mode 1 : LAMBDA_EXECUTOR=docker (par défaut)
→ Chaque Lambda est exécutée dans un conteneur Docker séparé.

Sur Windows + Docker Desktop : ce mode est instable et plante dès qu’on crée plusieurs Lambdas.

Preuve dans les logs :
'InternalError: Error while creating lambda: Docker not available'

Cela signifie que LocalStack ne parvient plus à lancer les conteneurs Lambda supplémentaires.

- Mode 2 : LAMBDA_EXECUTOR=local

Force l’exécution de Lambda hors Docker, directement dans le conteneur LocalStack.

Mais ce mode nécessite : modification profonde du docker-compose, montages de volumes spécifiques, installation des runtimes dans localstack, ...
et provoque des régressions dans d’autres services (API Gateway, S3)

Le professeur ne pourra pas reproduire ce mode automatiquement, surtout si son environnement n’est pas strictement identique.

# 2. Le multi-Lambda fonctionne sur AWS… mais pas sur un TP local

Sur AWS : chaque Lambda est déployée dans un environnement contrôlé

API Gateway intègre naturellement plusieurs lambdas.

Dans LocalStack, ce n’est pas le cas. LocalStack n’implémente pas 100 % du comportement réel pour Lambda.

Résultat :

- 1 Lambda fonctionne parfaitement
- 2 Lambda commencent à devenir instables
- 3+ Lambda échouent systématiquement

# 3. Pourquoi garder une seule Lambda est la solution optimale ici

Fonctionne 100 % du temps
Sur Windows, Mac, Linux, chez l'étudiant, chez le professeur.

Réduit les risques d’erreur dans un TP noté


L’architecture reste propre et le professeur peut tester sans configuration spéciale.

4. Pourquoi ne pas forcer malgré tout le multi-Lambda ?

Parce que même en réussissant à faire fonctionner localement :
- Le professeur ne pourra pas reproduire le résultat
- LocalStack est très sensible aux différences systèmes : version Docker Desktop, port 4566 déjà utilisé, Windows vs WSL, mode virtualization backend (Hyper-V vs WSL2), ...

Le même Terraform pourrait se mettre à échouer sur sa machine.

# Conclusion

Le choix de garder une seule Lambda n’est pas une simplification, mais une décision technique nécessaire liée aux limites connues de LocalStack dans un contexte Windows + Docker Desktop.

Cette architecture :
- résout les problèmes reproductibles
- garantit la portabilité
- respecte les objectifs pédagogiques du TP
- et reste parfaitement fidèle à une implémentation AWS réelle (API Gateway + Lambda + DynamoDB)


## Fichiers lambdas

'import json
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
    return make_response(200, updated)'

'import json
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

    return make_response(201, item)'

'import json

def make_response(status_code, body):
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
    return make_response(200, {"message": "Ahoy, pirate !"})'


'import json
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

    return make_response(200, items)'
