# Guía rápida del Makefile — users-managment-aws

> Todos los comandos se corren desde la **raíz de este repo** (donde está el `Makefile`).
> Prerrequisito: el cluster EKS `belo-challenge-dev` debe estar ACTIVE y `kubectl` apuntando a él.

---

## Flujo completo — primera vez (o re-deploy desde cero)

```bash
# 0. Limpiar CRBs del ciclo anterior (idempotente — no falla si no existen)
make rbac-migrate

# 1. Instalar el operador rbac-manager (ANTES de rbac-apply)
make rbac-manager-install

# 2. Inicializar Terraform para IAM (solo si es la primera vez o .terraform/ fue borrado)
make iam-init

# 3. Planear y aplicar recursos IAM
make iam-plan
make iam-apply

# 4. Guardar credenciales (se muestran UNA SOLA VEZ — copialas a un password manager)
make get-credentials

# 5. Configurar perfiles AWS CLI
aws configure --profile dev-user-01
aws configure --profile infra-user-01

# 6. Aplicar RBAC (aws-auth merge + ClusterRoles + Bindings + RBACDefinitions)
make rbac-apply

# 7. Verificar
make verify-developer
make verify-infra
```

> **Account ID:** si tu cuenta AWS no es `650790810564`, pasá el override:
> ```bash
> ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
> make verify-developer ACCOUNT=$ACCOUNT
> make verify-infra ACCOUNT=$ACCOUNT
> ```

---

## Referencia rápida de targets

| Target | Qué hace | Cuándo usarlo |
|--------|----------|---------------|
| `make help` | Lista todos los targets | Siempre |
| `make iam-init` | Inicializa backend Terraform de IAM | Primera vez o después de borrar `.terraform/` |
| `make iam-plan` | Plan de cambios IAM | Antes de apply |
| `make iam-apply` | Crea usuarios, grupos y roles IAM | Después del plan |
| `make iam-destroy` | Borra todos los recursos IAM | Teardown — pide confirmación |
| `make iam-output` | Muestra outputs (ARNs, etc.) | Para ver los ARNs de los roles creados |
| `make get-credentials` | Muestra las access keys | UNA SOLA VEZ post-iam-apply — guardalas ya |
| `make rbac-manager-install` | Instala el operador rbac-manager vía Helm | Primera vez por cluster — ANTES de rbac-apply |
| `make rbac-apply` | Aplica todo el RBAC (aws-auth + roles + bindings) | Después de rbac-manager-install |
| `make rbac-migrate` | Elimina CRBs del modelo anterior | Re-deploy, antes de rbac-apply |
| `make rbac-status` | Estado actual de ClusterRoles, Bindings y aws-auth | Debug |
| `make namespaces-apply` | Crea namespaces de aplicación | Lo hace automáticamente rbac-apply |
| `make env-apply` | Aplica RBACDefinitions de todos los ambientes | Re-aplicar después de cambios |
| `make env-apply-dev` | Aplica solo el RBACDefinition del ambiente dev | Cambios solo en dev |
| `make verify-developer` | Test de acceso como dev-user-01 | Después de rbac-apply |
| `make verify-infra` | Test de acceso como infra-user-01 | Después de rbac-apply |
| `make clean` | Borra archivos temporales (tfplan) | Limpieza |

---

## Variables override-ables

| Variable | Default | Para qué |
|----------|---------|----------|
| `CLUSTER` | `belo-challenge-dev` | Nombre del cluster EKS |
| `REGION` | `us-east-1` | Región AWS |
| `ACCOUNT` | `650790810564` | Account ID para construir el ARN del rol en verify-* |

Ejemplo: `make verify-developer CLUSTER=belo-challenge-staging ACCOUNT=123456789012`

---

## Agregar un nuevo usuario

```bash
# 1. Copiar template
cp templates/new-user.tf.template iam/users/nuevo-developer.tf
# 2. Editar placeholders en ese archivo
# 3. Planear y aplicar
make iam-plan
make iam-apply
make get-credentials   # para el nuevo usuario
```

## Agregar un namespace al acceso del grupo develop

```bash
# 1. Editar rbac/environments/dev/rbac-manager-dev.yaml
#    Agregar bajo roleBindings: { clusterRole: viewer-no-secrets, namespace: mi-nuevo-ns }
# 2. Aplicar solo el ambiente dev
make env-apply-dev
```
