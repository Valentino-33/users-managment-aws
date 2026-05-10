# Templates

Plantillas para escalar la gestión de usuarios y permisos sin tener que
inventar la rueda cada vez.

## Casos de uso

### Caso 1: agregar otro developer

El más común. Si solo necesitás un usuario más con los mismos permisos:

**Opción A (más limpia)** — agregar el nombre a la lista en `terraform.tfvars`:

```hcl
developers = ["dev-user-01", "dev-user-02", "alice"]
```

Y `terraform apply`. Listo.

**Opción B** — copiar el template:

```bash
cp templates/new-user.tf.template iam/user-alice.tf
# Editar iam/user-alice.tf con los datos
terraform apply
```

Usar la B solo si el usuario necesita configuración custom (tags distintos,
no querés generar access key, está en otro IAM group, etc.). Para casos
estándar, la A.

### Caso 2: crear un grupo nuevo (ej. "qa")

Tres pasos:

1. **Crear el ClusterRole con los permisos del grupo:**
   ```bash
   cp templates/new-clusterrole.yaml.template rbac/clusterroles/qa-readonly.yaml
   # Editar las reglas según lo que pueda/no pueda hacer QA
   kubectl apply -f rbac/clusterroles/qa-readonly.yaml
   ```

2. **Crear el ClusterRoleBinding que enchufa el grupo K8s al ClusterRole:**
   ```bash
   cp templates/new-group-binding.yaml.template rbac/bindings/qa-binding.yaml
   # Editar para que `subjects.name = qa` y `roleRef.name = qa-readonly`
   kubectl apply -f rbac/bindings/qa-binding.yaml
   ```

3. **Mapear un rol/user IAM al grupo K8s en aws-auth:**
   ```bash
   kubectl edit cm aws-auth -n kube-system
   # Agregar manualmente al campo data.mapRoles:
   #   - rolearn: arn:aws:iam::<account>:role/qa-engineer
   #     username: qa:{{SessionName}}
   #     groups:
   #       - qa
   ```
   Si querés automatizar este paso, el script `scripts/merge-aws-auth.sh`
   se puede adaptar copiándolo y agregando las nuevas variables.

### Caso 3: dar permisos extra a un grupo existente

Dos opciones según el alcance del cambio:

- **Cambio chico** (ej. permitir `kubectl exec` al grupo `develop`): editar
  directamente `rbac/clusterroles/viewer-no-secrets.yaml` y agregar la regla.
  Re-apply.
- **Cambio grande** (ej. crear un perfil "developer-senior" con permisos
  intermedios): mejor un ClusterRole nuevo + ClusterRoleBinding nuevo, así no
  rompés el perfil base y podés migrar usuarios uno por uno.

## Convenciones que usamos

- **Nombres:** kebab-case para K8s (`qa-readonly`, `platform-team-admin`),
  snake_case para nombres internos de Terraform (`platform_team`).
- **Labels:** todo recurso de RBAC lleva `app.kubernetes.io/managed-by:
  users-managment-aws` para distinguirlo de cosas creadas a mano.
- **Username pattern en aws-auth:** siempre con `{{SessionName}}` al final,
  ej: `qa:{{SessionName}}`. Esto hace que en los audit logs aparezca
  `qa:alice` en lugar de un genérico, útil para trackear quién hizo qué.
- **Path IAM:** todos los users e IAM roles llevan path
  `/<cluster_name>/`, lo que permite filtrar por cluster cuando hay varios.

## Rollback

Si una nueva regla / grupo / usuario rompe algo:

```bash
# Volver atrás un manifest:
git revert HEAD --no-edit
kubectl apply -f rbac/

# Volver atrás Terraform:
cd iam && terraform apply -refresh-only  # ver el drift
# y después aplicar el HEAD anterior
```

Para aws-auth específicamente, el script `merge-aws-auth.sh` deja un backup
en `/tmp/aws-auth-backups/` con timestamp. Para restaurar:

```bash
ls /tmp/aws-auth-backups/  # ver los backups disponibles
kubectl apply -f /tmp/aws-auth-backups/aws-auth-<timestamp>.yaml
```
