resource "aws_eks_node_group" "academy_test" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng-academy"

  node_role_arn = "arn:aws:iam::748689320321:role/c230972a5811316l18408252t1w748689320-LabEksNodeRole-cR2NZm3fQEfu"

  subnet_ids     = var.node_subnet_ids
  instance_types = var.node_instance_types
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"

  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 2
  }

  tags = {
    Name = "${var.cluster_name}-ng-academy"
  }
}
