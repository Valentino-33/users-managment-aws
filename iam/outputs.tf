output "developer_role_arn" {
  description = "ARN del rol que asumen los developers. Va en aws-auth y en el comando update-kubeconfig."
  value       = aws_iam_role.developer.arn
}

output "infra_role_arn" {
  description = "ARN del rol que asumen los infra operators."
  value       = aws_iam_role.infra.arn
}

output "developer_users" {
  description = "Lista de IAM users con rol developer."
  value       = [for u in aws_iam_user.developers : u.name]
}

output "infra_users" {
  description = "Lista de IAM users con rol infra."
  value       = [for u in aws_iam_user.infra : u.name]
}

# ──────────────── Access keys ────────────────
# Marcado como sensitive para que no aparezcan en logs por accidente.
# Se ven con: terraform output -json access_keys
# Se ven UNA VEZ — guardarlas en password manager y borrar el state si te
# preocupa que queden en S3 (están encriptadas, pero igual).

output "access_keys" {
  description = "Access keys iniciales. Solo se generan si create_access_keys=true."
  sensitive   = true
  value = merge(
    {
      for u, k in aws_iam_access_key.developers : u => {
        access_key_id     = k.id
        secret_access_key = k.secret
        role_to_assume    = aws_iam_role.developer.arn
      }
    },
    {
      for u, k in aws_iam_access_key.infra : u => {
        access_key_id     = k.id
        secret_access_key = k.secret
        role_to_assume    = aws_iam_role.infra.arn
      }
    }
  )
}

# ──────────────── Helpers para aws-auth ────────────────
# Estos outputs los usa el script merge-aws-auth.sh para construir el bloque
# que se mergea en el ConfigMap. No editar a mano.

output "aws_auth_map_roles_addition" {
  description = "Bloque YAML para agregar a mapRoles del aws-auth ConfigMap."
  value = <<-EOT
    - rolearn: ${aws_iam_role.developer.arn}
      username: developer:{{SessionName}}
      groups:
        - develop
    - rolearn: ${aws_iam_role.infra.arn}
      username: infra:{{SessionName}}
      groups:
        - Infra
  EOT
}

output "kubeconfig_cmd_developer" {
  description = "Comando listo para copiar/pegar."
  value = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region} --profile <PROFILE> --role-arn ${aws_iam_role.developer.arn} --alias dev"
}

output "kubeconfig_cmd_infra" {
  value = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region} --profile <PROFILE> --role-arn ${aws_iam_role.infra.arn} --alias infra"
}
