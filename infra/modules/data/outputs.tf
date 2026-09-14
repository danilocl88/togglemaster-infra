output "rds_endpoints" {
  value = {
    for k, v in aws_db_instance.postgres :
    k => v.address
  }
}

output "rds_database_urls" {
  sensitive = true

  value = {
    for k, v in aws_db_instance.postgres :
    k => "postgresql://tmadmin:${random_password.db[k].result}@${v.address}:5432/${v.db_name}"
  }
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}
