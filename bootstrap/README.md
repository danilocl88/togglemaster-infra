# Bootstrap do backend S3

No AWS Academy, a criacao do bucket com aws_s3_bucket foi abandonada porque
uma Service Control Policy nega explicitamente s3:GetBucketObjectLockConfiguration.

O bucket do backend e criado/configurado por create-backend.sh usando AWS CLI.
A infraestrutura principal continua sendo provisionada por Terraform e grava
seu state remotamente no S3, em infra/terraform.tfstate, com use_lockfile=true.

Nao existe state Terraform do bootstrap.
