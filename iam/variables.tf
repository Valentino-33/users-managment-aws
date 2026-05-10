variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "cluster_name" {
  description = "Nombre del cluster EKS al que estos roles van a tener acceso. Se usa para nombrar los IAM roles."
  type        = string
  default     = "belo-challenge-dev"
}

# ──────────────── Usuarios iniciales ────────────────
# Lista de usuarios a crear, con su grupo IAM. Para agregar más, copiar
# este bloque o usar templates/new-user.tf.template.

variable "developers" {
  description = "Usuarios iniciales que pertenecen al grupo 'developers' (acceso K8s read-only sin secrets)."
  type        = list(string)
  default     = ["dev-user-01"]
}

variable "infra_operators" {
  description = "Usuarios iniciales que pertenecen al grupo 'infra-operators' (acceso K8s admin)."
  type        = list(string)
  default     = ["infra-user-01"]
}

variable "create_access_keys" {
  description = "Si crear access keys IAM iniciales. true para demo, false en producción real (mejor IAM Identity Center)."
  type        = bool
  default     = true
}
