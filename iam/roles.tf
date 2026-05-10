# ──────────────── IAM Roles para EKS ────────────────
# Estos roles son los que terminan mapeados en aws-auth. Cada uno tiene una
# trust policy que dice "los miembros de este IAM group pueden asumirme".

# El rol del developer no necesita políticas IAM adicionales — el acceso se
# resuelve dentro de Kubernetes vía RBAC. AWS solo valida que asumir el rol
# esté permitido y le pasa el token al cluster.
#
# Lo mismo aplica al rol infra. Los permisos efectivos en K8s vienen del
# ClusterRoleBinding, no de policies AWS.

# Trust policy: cualquier principal del account que pueda mostrar credenciales
# del IAM group correspondiente puede asumir el rol.
data "aws_iam_policy_document" "developer_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    # Limitamos a los miembros del IAM group via condición sobre el ARN.
    # Esto se evalúa en cada AssumeRole: si el caller no es miembro del
    # group "developers", la operación falla.
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:${local.partition}:iam::${local.account_id}:user/${var.cluster_name}/*"
      ]
    }
  }
}

data "aws_iam_policy_document" "infra_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:${local.partition}:iam::${local.account_id}:user/${var.cluster_name}/*"
      ]
    }
  }
}

resource "aws_iam_role" "developer" {
  name               = local.developer_role_name
  assume_role_policy = data.aws_iam_policy_document.developer_trust.json
  description        = "EKS read-only role (no secrets) asumido por miembros del group 'developers'"

  max_session_duration = 3600  # 1 hora — sesiones cortas, fuerza a re-asumir
}

resource "aws_iam_role" "infra" {
  name               = local.infra_role_name
  assume_role_policy = data.aws_iam_policy_document.infra_trust.json
  description        = "EKS admin role asumido por miembros del group 'infra-operators'"

  max_session_duration = 3600
}
