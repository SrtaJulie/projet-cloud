# ---------------------------------------------------------------
# DYNAMODB TABLE
# ---------------------------------------------------------------
resource "aws_dynamodb_table" "bounties" {
  name         = "Bounties"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # NOTE:
  # En prod AWS, on activerait le chiffrement côté serveur (SSE) ici.
  # Sur LocalStack, le bloc server_side_encryption provoque des erreurs
  # CreateTable / ResourceInUseException, donc il est volontairement omis.
  #
  # Exemple (à utiliser en VRAI AWS, pas dans ce TP LocalStack) :
  #
  # server_side_encryption {
  #   enabled = true
  # }
}