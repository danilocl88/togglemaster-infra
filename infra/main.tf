data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr

  azs = local.azs

  public_subnet_cidrs = [
    "10.30.0.0/24",
    "10.30.1.0/24"
  ]

  private_subnet_cidrs = [
    "10.30.10.0/24",
    "10.30.11.0/24"
  ]
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.project_name
  kubernetes_version = var.kubernetes_version
  lab_role_arn       = var.lab_role_arn

  cluster_subnet_ids = concat(
    module.network.public_subnet_ids,
    module.network.private_subnet_ids
  )

  node_subnet_ids     = module.network.public_subnet_ids
  node_instance_types = var.node_instance_types
}

module "data" {
  source = "./modules/data"

  project_name          = var.project_name
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  eks_security_group_id = module.eks.cluster_security_group_id
  db_instance_class     = var.db_instance_class
  redis_node_type       = var.redis_node_type
}

module "services" {
  source = "./modules/services"

  project_name = var.project_name
}
