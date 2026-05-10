# ──────────────── IAM Groups ────────────────
# Los grupos no tienen permisos sobre AWS por sí mismos — solo permiten a sus
# miembros asumir el role IAM correspondiente. Esa es la única puerta de
# entrada al cluster.

resource "aws_iam_group" "developers" {
  name = "developers"
  path = "/${var.cluster_name}/"
}

resource "aws_iam_group" "infra_operators" {
  name = "infra-operators"
  path = "/${var.cluster_name}/"
}

# ──────────────── Group policies (sts:AssumeRole) ────────────────

data "aws_iam_policy_document" "assume_developer_role" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [local.developer_role_arn]
  }

  # eks:DescribeCluster es invocado por el CLI al ejecutar `aws eks update-kubeconfig`
  statement {
    effect  = "Allow"
    actions = ["eks:DescribeCluster"]
    resources = [
      "arn:${local.partition}:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"
    ]
  }
}

data "aws_iam_policy_document" "assume_infra_role" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [local.infra_role_arn]
  }

  statement {
    effect  = "Allow"
    actions = ["eks:DescribeCluster"]
    resources = [
      "arn:${local.partition}:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"
    ]
  }
}

resource "aws_iam_group_policy" "developers_assume" {
  name   = "assume-eks-developer"
  group  = aws_iam_group.developers.name
  policy = data.aws_iam_policy_document.assume_developer_role.json
}

resource "aws_iam_group_policy" "infra_assume" {
  name   = "assume-eks-infra"
  group  = aws_iam_group.infra_operators.name
  policy = data.aws_iam_policy_document.assume_infra_role.json
}
