output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_node_group_name" {
  value = module.eks.node_group_name
}

output "rds_endpoints" {
  value = module.data.rds_endpoints
}

output "redis_endpoint" {
  value = module.data.redis_endpoint
}

output "dynamodb_table_name" {
  value = module.services.dynamodb_table_name
}

output "sqs_queue_url" {
  value = module.services.sqs_queue_url
}

output "sqs_queue_arn" {
  value = module.services.sqs_queue_arn
}

output "ecr_repository_urls" {
  value = module.services.ecr_repository_urls
}

output "rds_database_urls" {
  value     = module.data.rds_database_urls
  sensitive = true
}
