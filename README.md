# Projet PRIMES PIRATES

Ce répository à été créé dans le cadre de notre M2 et du projet du module de formation "Développement dans le cloud" à l'Université Toulouse Capitole.

## PRIMES PIRATES

Primes Pirate est une application "tableau de primes" où des pirates postent des primes (bounties), d’autres les revendiquent avec preuve (texte). L'application est hébergée grâce au service S3 (LocalStack). Une API Gateway est en interaction avec 4 Lambdas (dans 4 fichiers différents). Les bounties sont stockées dans une base de données DynamoDB. L'IAC est mise en place grâce à un fichier Terraform.

## Equipe

Julie BONNET
- login GitHub : @SrtaJulie
- mail universitaire : julie5.bonnet@ut-capitole.fr

Océane ETOUBLEAU-ETIENNE
- login GitHub : @HellOShael

Adrien LISTL
- login GitHub : @craftlistl


## Build du projet - Important

Les secrets sont en exemple dans le fichier : secrets.tfvars.example, il faut renommer le fichier enlever le .example.
Pour lancer le tofu apply avec les secrets : tofu apply -var-file="secrets.tfvars"

Dans chaque fichier HTML, il faut mettre à jour cette ligne après avoir fait une première fois "tofu apply" : API_BASE = "http://localhost:4566/restapis/eu85g5yiyt/dev/_user_request_"

L'identifiant de l'API change à chaque premier build.
Ici exemple identifiant = eu85g5yiyt

Vous pouvez le trouver dans le terminal, la variable "base_url" du output.

