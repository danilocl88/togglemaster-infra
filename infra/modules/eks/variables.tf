variable "cluster_name" { type = string }
variable "kubernetes_version" { type = string }
variable "lab_role_arn" { type = string }
variable "cluster_subnet_ids" { type = list(string) }
variable "node_subnet_ids" { type = list(string) }
variable "node_instance_types" { type = list(string) }
