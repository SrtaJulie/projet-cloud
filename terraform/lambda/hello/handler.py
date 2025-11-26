from terraform.lambda.common.common import response

def handler(event, context):
    return response(200, {"message": "Hello Pirate!"})