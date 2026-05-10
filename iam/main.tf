data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Nombres consistentes para los roles. Si se cambia el cluster, los roles
  # quedan automáticamente referenciados por el nuevo nombre.
  developer_role_name = "${var.cluster_name}-eks-developer"
  infra_role_name     = "${var.cluster_name}-eks-infra"

  developer_role_arn = "arn:${local.partition}:iam::${local.account_id}:role/${local.developer_role_name}"
  infra_role_arn     = "arn:${local.partition}:iam::${local.account_id}:role/${local.infra_role_name}"
}
