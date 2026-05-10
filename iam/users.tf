# ──────────────── Developer users ────────────────

resource "aws_iam_user" "developers" {
  for_each = toset(var.developers)

  name = each.key
  path = "/${var.cluster_name}/"

  # force_destroy permite borrar el user aunque tenga keys/console-login activos.
  # Útil para demo. En prod, dejar en false y limpiar manualmente.
  force_destroy = true

  tags = {
    role  = "developer"
    group = "developers"
  }
}

resource "aws_iam_user_group_membership" "developers" {
  for_each = aws_iam_user.developers

  user   = each.value.name
  groups = [aws_iam_group.developers.name]
}

# ──────────────── Infra operator users ────────────────

resource "aws_iam_user" "infra" {
  for_each = toset(var.infra_operators)

  name = each.key
  path = "/${var.cluster_name}/"

  force_destroy = true

  tags = {
    role  = "infra-operator"
    group = "infra-operators"
  }
}

resource "aws_iam_user_group_membership" "infra" {
  for_each = aws_iam_user.infra

  user   = each.value.name
  groups = [aws_iam_group.infra_operators.name]
}

# ──────────────── Access keys (opcional, demo only) ────────────────
# En producción usar IAM Identity Center (ex SSO) en lugar de access keys
# de larga vida. Para una demo donde los usuarios no son humanos reales,
# está OK.

resource "aws_iam_access_key" "developers" {
  for_each = var.create_access_keys ? aws_iam_user.developers : {}
  user     = each.value.name
}

resource "aws_iam_access_key" "infra" {
  for_each = var.create_access_keys ? aws_iam_user.infra : {}
  user     = each.value.name
}
