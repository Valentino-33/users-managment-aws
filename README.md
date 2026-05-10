# users-managment-aws

Gestión de usuarios, grupos, roles IAM y autorización RBAC para el cluster
EKS `belo-challenge-dev`. Cubre el caso del challenge (1 developer + 1 infra
operator) y deja templates listos para escalar y archivos preparados para
activar OIDC más adelante.

## Cómo se conectan las piezas

Hay dos capas de seguridad encadenadas. Una vive en AWS, la otra en
Kubernetes. Entender cómo se comunican es clave:

```
  ┌─────────────┐   sts:AssumeRole   ┌─────────────────┐
  │  IAM User   │ ─────────────────▶ │   IAM Role      │
  │ dev-user-01 │                    │ eks-developer   │
  └─────────────┘                    └─────────────────┘
                                              │
                                              │ aws-auth ConfigMap
                                              │ mapea rolearn → grupo K8s
                                              ▼
                                     ┌─────────────────┐
                                     │  K8s Group      │
                                     │   "develop"     │
                                     └─────────────────┘
                                              │
                                              │ RoleBinding (por namespace)
                                              │ generado por rbac-manager
                                              ▼
                                   ┌──────────────────────┐
                                   │     ClusterRole      │
                                   │  viewer-no-secrets   │
                                   │                      │
                                   │ pods / logs /        │
                                   │ deployments / etc.   │
                                   │ get namespace (*)    │
                                   │ sin secrets          │
                                   └──────────────────────┘
                                              │
                               ┌──────────────┴──────────────┐
                               │  Namespaces de aplicación   │
                               │  (rbac/environments/dev/)   │
                               │                             │
                               │  ✓ belo-challenge-dev       │
                               │  ✗ kube-system (excluido)   │
                               │  ✗ kube-public (excluido)   │
                               │  ✗ default (excluido)       │
                               └─────────────────────────────┘
```

> (*) `get namespace` es solo el verbo `get` (GET singular). El verbo `list`
> no está otorgado, por lo que `kubectl get namespaces` devuelve **Forbidden**.
> Ver nota sobre namespaces más abajo.

Cada capa hace una cosa:

1. **IAM User** — quién es la persona ante AWS (access key + secret key).
2. **IAM Role + sts:AssumeRole** — la persona se "pone el sombrero" del rol
   que necesita para esta sesión. Da audit trail (CloudTrail loggea cada
   assume) y separa identidad de permisos.
3. **aws-auth ConfigMap** — le dice al cluster: "este IAM role corresponde a
   este grupo K8s".
4. **K8s Group** — etiqueta usada por RBAC. No existe como recurso — es solo
   un nombre que aparece en aws-auth y en los Bindings.
5. **RoleBinding (por namespace) → `viewer-no-secrets`** — generado
   automáticamente por rbac-manager a partir de la `RBACDefinition`. Da
   acceso de lectura (pods, deployments, logs, configmaps, etc.) solo dentro
   de los namespaces de aplicación declarados en `rbac/environments/<env>/`.
   El ClusterRole incluye el verbo `get` sobre `namespaces` para permitir
   inspeccionar el propio namespace (`kubectl get namespace belo-challenge-dev`)
   pero **no** el verbo `list`, por lo que listar todos los namespaces queda
   Forbidden.

### Nota sobre namespaces y RBAC nativo

Los namespaces son recursos **cluster-scoped** en Kubernetes. No existe
mecanismo RBAC nativo para filtrar `kubectl get namespaces` a un subconjunto:
o se listan **todos** (vía ClusterRoleBinding) o la operación devuelve
Forbidden. Para evitar que los developers vean los namespaces de sistema
(`kube-system`, `kube-public`, etc.), el modelo deliberadamente **no** otorga
el verbo `list` sobre `namespaces`. Solo otorga `get` (acceso singular), que
es suficiente para `kubectl get namespace belo-challenge-dev`.

Si en el futuro se necesita listar namespaces filtrados, la única solución es
un admission webhook (OPA/Kyverno) que intercepte y filtre las respuestas —
fuera del scope de RBAC nativo.

## Estructura del repo

```
users-managment-aws/
├── iam/                        # Terraform: IAM users, groups, roles, policies
├── rbac/
│   ├── clusterroles/           # ClusterRoles reutilizables
│   │   ├── viewer-no-secrets.yaml    # Lectura completa sin secrets (para devs)
│   │   └── list-namespaces.yaml      # Solo get/list/watch namespaces (no asignado a devs)
│   ├── bindings/               # ClusterRoleBindings globales
│   │   └── infra-binding.yaml        # Infra → cluster-admin
│   └── environments/           # RBACDefinitions por ambiente (rbac-manager)
│       └── dev/
│           └── rbac-manager-dev.yaml # RBACDefinition: acceso del grupo develop en dev
├── scripts/                    # Helpers (ej. merge seguro de aws-auth)
├── templates/                  # Plantillas para crear nuevos users/groups
└── oidc/                       # Archivos OIDC preparados pero desactivados
```

> **Nota sobre develop-binding.yaml:** no existe un ClusterRoleBinding para el grupo develop
> porque el modelo usa RoleBindings namespaceados (generados por rbac-manager). Un CRB daría
> acceso cluster-wide, que es exactamente lo que se quiere evitar.

## Qué se crea

### En IAM (Terraform)

| Recurso | Nombre | Para qué |
|---|---|---|
| IAM Group | `developers` | Permite a sus miembros asumir el rol developer |
| IAM Group | `infra-operators` | Permite a sus miembros asumir el rol infra |
| IAM Role | `belo-challenge-dev-eks-developer` | Trust policy: usuarios del grupo `developers` |
| IAM Role | `belo-challenge-dev-eks-infra` | Trust policy: usuarios del grupo `infra-operators` |
| IAM User | `dev-user-01` | Ejemplo de developer (miembro de `developers`) |
| IAM User | `infra-user-01` | Ejemplo de operador (miembro de `infra-operators`) |

### En Kubernetes (manifestos)

| Recurso | Tipo | Alcance | Para qué |
|---|---|---|---|
| `viewer-no-secrets` | ClusterRole | cluster | Lectura completa sin secrets; `namespaces` con verbo `get` únicamente (no `list`) |
| `list-namespaces` | ClusterRole | cluster | `get/list/watch namespaces` — disponible pero no asignado al grupo developer |
| `cluster-admin` | ClusterRole | cluster | (built-in) — acceso total para infra |
| `infra-admin` | ClusterRoleBinding | cluster | Grupo `Infra` → `cluster-admin` |
| `rbac-manager-dev-groups` | RBACDefinition | cluster | Grupo `develop` → `viewer-no-secrets` solo en namespaces de app del ambiente dev |
| `aws-auth` | ConfigMap (kube-system) | cluster | Mapea roles IAM → grupos K8s |

> **Por qué no hay ClusterRoleBinding para el grupo develop:** otorgar un
> ClusterRoleBinding con `list namespaces` haría que los developers vieran
> también `kube-system`, `kube-public`, etc. El modelo usa solo RoleBindings
> (generados por rbac-manager) para acotar el acceso a los namespaces de
> aplicación declarados explícitamente.

> **Cómo funciona rbac-manager:** el operador (Fairwinds) observa los recursos
> `RBACDefinition` y crea automáticamente los `RoleBindings` en cada namespace
> listado. Al no declarar los namespaces de sistema, los developers quedan
> excluidos de ellos sin necesidad de deny rules. Cada ambiente tiene su
> propio archivo en `rbac/environments/<env>/`.

## Pasos para concluir la implementación

### Prerrequisitos

- El cluster `belo-challenge-dev` debe estar levantado.
- `kubectl` apuntando al cluster correcto (`kubectl config current-context`).
- AWS CLI instalado y configurado con credenciales de administrador.
- `helm` instalado (solo para el paso 1).

### Paso 1 — Instalar rbac-manager (solo la primera vez por cluster)

```bash
make rbac-manager-install
```

Instala el operador Fairwinds `rbac-manager` vía Helm en el namespace
`rbac-manager`. Si ya está corriendo (`kubectl get pods -n rbac-manager`),
saltear este paso.

### Paso 2 — Aplicar IAM con Terraform

```bash
make iam-init        # solo si nunca se corrió antes
make iam-plan
make iam-apply
make get-credentials # guardar en password manager — las keys solo se ven una vez
```

Si ya se corrió `make iam-apply` previamente y tenés las keys guardadas,
saltar al paso 3.

### Paso 3 — Configurar perfiles AWS CLI con las credenciales IAM

```bash
aws configure --profile dev-user-01
# Access Key ID:     (el que salió en get-credentials)
# Secret Access Key: (el que salió en get-credentials)
# Region:            us-east-1
# Output format:     json

aws configure --profile infra-user-01
# (ídem con las keys de infra-user-01)
```

### Paso 4 — Limpiar ClusterRoleBindings del modelo anterior

Siempre es seguro correr este comando — ignora si los recursos no existen.
Es necesario si el cluster tenía los CRBs `develop-viewer` o
`develop-list-namespaces` de una versión anterior (con esos CRBs el developer
puede listar todos los namespaces, rompiendo el modelo de acceso acotado).

```bash
make rbac-migrate
```

Para verificar si había CRBs viejos:
```bash
kubectl get clusterrolebinding | grep develop
```
Si la salida está vacía o no muestra `develop-viewer` ni `develop-list-namespaces`,
el cluster ya estaba limpio.

### Paso 5 — Aplicar RBAC

```bash
make rbac-apply
```

Aplica en orden:
1. `aws-auth` merge (mapeo IAM roles → grupos K8s)
2. ClusterRoles (`viewer-no-secrets`, `list-namespaces`)
3. ClusterRoleBindings (`infra-admin`)
4. Namespace de aplicación (`belo-challenge-dev`) — requerido para que
   rbac-manager pueda crear el RoleBinding
5. RBACDefinitions (genera el RoleBinding del grupo `develop` en el namespace)

> **Por qué se crea el namespace en este paso:** rbac-manager genera
> RoleBindings dentro de los namespaces declarados en la RBACDefinition. Si el
> namespace no existe en el momento de la reconciliación, el RoleBinding no se
> crea y el developer queda sin acceso. `make rbac-apply` incluye
> `namespaces-apply` para garantizar que el namespace exista antes de que
> rbac-manager reconcilie.

### Paso 6 — Verificar

```bash
make verify-developer
```

Resultado esperado:

| Comando | Resultado esperado |
|---|---|
| `kubectl get namespaces` | ✗ Forbidden |
| `kubectl get namespace belo-challenge-dev` | ✓ Muestra el namespace |
| `kubectl get pods -n belo-challenge-dev` | ✓ Lista pods (vacío si no hay pods) |
| `kubectl get pods -n kube-system` | ✗ Forbidden |
| `kubectl get secrets -n belo-challenge-dev` | ✗ Forbidden |

```bash
make verify-infra
```

`infra-user-01` debe poder ver nodos, secrets de cualquier namespace y tener
acceso total al cluster.

> **Nota sobre kubeconfig:** los comandos `make verify-developer` y
> `make verify-infra` actualizan el kubeconfig con los contextos `verify-dev`
> y `verify-infra`. El contexto de administrador que uses para operar el cluster
> debe estar configurado con un user entry separado (ej. sin `--role-arn` y con
> las credenciales del usuario admin). Si el contexto admin queda afectado,
> restaurarlo con:
> ```bash
> aws eks update-kubeconfig --name belo-challenge-dev --region us-east-1 --alias admin-ctx
> ```

## Cómo se loguea un developer (paso a paso)

Después de que un admin creó las access keys IAM y se las pasó al developer:

```bash
# 1. El developer configura su perfil en AWS CLI
aws configure --profile dev-user-01
# (pegar access key id, secret, región us-east-1)

# 2. Configura kubectl para asumir el rol developer al hablar con EKS
aws eks update-kubeconfig \
  --name belo-challenge-dev \
  --region us-east-1 \
  --profile dev-user-01 \
  --role-arn arn:aws:iam::650790810564:role/belo-challenge-dev-eks-developer \
  --alias dev

# 3. Probá
kubectl --context dev get namespaces                           # ✗ Forbidden
kubectl --context dev get namespace belo-challenge-dev         # ✓ GET singular del propio ns
kubectl --context dev get pods -n belo-challenge-dev           # ✓ acceso en ns de app
kubectl --context dev get pods -n kube-system                  # ✗ Forbidden
kubectl --context dev get secrets -n belo-challenge-dev        # ✗ Forbidden
kubectl --context dev delete pod xxx -n belo-challenge-dev     # ✗ Forbidden
```

## Para escalar (más usuarios, grupos o ambientes)

Ver [`templates/README.md`](./templates/README.md). Hay tres plantillas:

- **`new-user.tf.template`** — para agregar otro IAM user dentro de un grupo
  existente. Copiás, completás placeholders, `terraform apply`.
- **`new-clusterrole.yaml.template`** — para crear un nuevo perfil de
  permisos K8s (ej. "platform-engineer" con permisos intermedios).
- **`new-group-binding.yaml.template`** — para enchufar un nuevo grupo K8s a
  un ClusterRole.

### Agregar un namespace de aplicación al ambiente dev

Editá `rbac/environments/dev/rbac-manager-dev.yaml` y agregá un bloque dentro
del `roleBindings` existente:

```yaml
- clusterRole: viewer-no-secrets
  namespace: mi-nuevo-namespace
```

Luego aplicá:

```bash
make env-apply-dev
```

rbac-manager detecta el cambio y crea el `RoleBinding` en ese namespace automáticamente.

### Agregar un nuevo ambiente (ej. staging)

```bash
mkdir -p rbac/environments/staging
# Crear rbac/environments/staging/rbac-manager-staging.yaml con el mismo
# formato RBACDefinition, cambiando los namespaces correspondientes
make env-apply   # aplica todos los ambientes de una vez
```

## OIDC — preparado pero desactivado

Los archivos para integrar un IDP externo (Cognito, Okta, Auth0, Google) están
en `oidc/`. Cuando se decida activarlos, se siguen los pasos de
[`oidc/README.md`](./oidc/README.md). No requieren cambios al código actual,
solo agregarse al stack.

Mientras OIDC esté desactivado, la autenticación va por IAM como muestra el
diagrama de arriba.
