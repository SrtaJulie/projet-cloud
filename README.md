Les secrets sont en exemple dans le fichier : secrets.tfvars.example (il faut enlever le .example)
Pour lancer le tofu avec les secrets : tofu apply -var-file="secrets.tfvars"

Si sur la page du site les données ne chargent pas il faut changer dans les scripts des pages html : 
    const API_BASE
Par le base_url renvoyé apres le apply de terraform
