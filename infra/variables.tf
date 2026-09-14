variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "togglemaster-fase3"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "kubernetes_version" {
  type        = string
  description = "Versao EKS suportada pelo laboratorio. Ajuste se necessario."
  default     = "1.36"
}

variable "lab_role_arn" {
  type        = string
  description = "ARN da LabRole existente no AWS Academy. Terraform NAO cria IAM role."
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}
