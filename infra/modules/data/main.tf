locals {
  databases = {
    auth      = { db_name = "auth_db" }
    flag      = { db_name = "flags_db" }
    targeting = { db_name = "targeting_db" }
  }
}

resource "random_password" "db" {
  for_each = local.databases

  length  = 24
  special = false
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "PostgreSQL somente a partir do EKS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }


  # Deny explicit outbound rules. Security Groups are stateful;
  # response traffic for permitted inbound connections remains allowed.
  egress = []
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "postgres" {
  for_each = local.databases

  identifier = "${var.project_name}-${each.key}-db"

  engine         = "postgres"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = each.value.db_name
  username = "tmadmin"
  password = random_password.db[each.key].result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true
}

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Redis somente a partir do EKS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }


  # Deny explicit outbound rules. Security Groups are stateful;
  # response traffic for permitted inbound connections remains allowed.
  egress = []
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id = "${var.project_name}-redis"

  engine          = "redis"
  node_type       = var.redis_node_type
  num_cache_nodes = 1
  port            = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]
}
