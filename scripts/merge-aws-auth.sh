#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# merge-aws-auth.sh
# ─────────────────────────────────────────────────────────────────────────────
# El ConfigMap aws-auth en kube-system contiene los mapeos IAM→K8s. Las
# entradas existentes (los node groups y Karpenter) NO se pueden pisar — si
# las borrás, los nodos pierden acceso al cluster y todo deja de funcionar.
#
# Este script:
#   1. Lee el aws-auth actual.
#   2. Le pega encima nuestras adiciones (developer y infra roles).
#   3. Aplica el resultado sin tocar las entradas existentes.
#
# Estrategia: usamos `kubectl patch` en modo strategic-merge sobre el campo
# data.mapRoles, que es un string YAML embebido. Como es un string, no se
# puede mergear en JSON directamente — hay que armar el bloque a mano y
# detectar si las entradas ya existen para no duplicar.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Validaciones ──
if ! command -v kubectl >/dev/null; then
  echo "❌ kubectl no está instalado o no está en el PATH"
  exit 1
fi

if ! kubectl get cm aws-auth -n kube-system >/dev/null 2>&1; then
  echo "❌ No existe el ConfigMap aws-auth en kube-system."
  echo "   ¿Está el cluster levantado y kubectl apuntando al cluster correcto?"
  echo "   Ejecutá: kubectl config current-context"
  exit 1
fi

# ── Obtener los ARNs de Terraform ──
cd "$(dirname "$0")/../iam"

if [ ! -d .terraform ]; then
  echo "❌ El módulo Terraform de IAM no está inicializado."
  echo "   Ejecutá: make iam-init && make iam-apply"
  exit 1
fi

DEV_ARN=$(terraform output -raw developer_role_arn 2>/dev/null || echo "")
INFRA_ARN=$(terraform output -raw infra_role_arn 2>/dev/null || echo "")

if [ -z "$DEV_ARN" ] || [ -z "$INFRA_ARN" ]; then
  echo "❌ No pude leer los ARNs del Terraform de IAM."
  echo "   ¿Corriste 'make iam-apply'?"
  exit 1
fi

cd - > /dev/null

# ── Backup del aws-auth actual ──
BACKUP_DIR="/tmp/aws-auth-backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/aws-auth-$(date +%Y%m%d-%H%M%S).yaml"
kubectl get cm aws-auth -n kube-system -o yaml > "$BACKUP_FILE"
echo "✓ Backup en $BACKUP_FILE"

# ── Detectar si las entradas ya existen ──
CURRENT=$(kubectl get cm aws-auth -n kube-system -o jsonpath='{.data.mapRoles}')

if echo "$CURRENT" | grep -q "$DEV_ARN"; then
  echo "ℹ  El rol developer ya está mapeado en aws-auth. No hago nada para él."
  ADD_DEV=false
else
  ADD_DEV=true
fi

if echo "$CURRENT" | grep -q "$INFRA_ARN"; then
  echo "ℹ  El rol infra ya está mapeado en aws-auth. No hago nada para él."
  ADD_INFRA=false
else
  ADD_INFRA=true
fi

if [ "$ADD_DEV" = false ] && [ "$ADD_INFRA" = false ]; then
  echo "✓ aws-auth ya tiene las dos entradas. No hay nada para hacer."
  exit 0
fi

# ── Construir el bloque a agregar ──
ADDITION=""
if [ "$ADD_DEV" = true ]; then
  ADDITION="${ADDITION}
- rolearn: ${DEV_ARN}
  username: developer:{{SessionName}}
  groups:
    - develop"
fi
if [ "$ADD_INFRA" = true ]; then
  ADDITION="${ADDITION}
- rolearn: ${INFRA_ARN}
  username: infra:{{SessionName}}
  groups:
    - Infra"
fi

# ── Construir el nuevo mapRoles concatenado ──
NEW_MAP_ROLES="${CURRENT}${ADDITION}"

# ── Aplicar el patch ──
# kubectl patch --type=merge acepta un JSON donde data.mapRoles es un string.
# Solo necesitamos escapar el contenido para JSON puro bash (sin dependencias externas).

json_escape_str() {
  local s="$1"
  s="${s//\\/\\\\}"    # \ → \\
  s="${s//\"/\\\"}"    # " → \"
  s="${s//$'\n'/\\n}"  # LF → \n
  s="${s//$'\r'/\\r}"  # CR → \r
  s="${s//$'\t'/\\t}"  # TAB → \t
  printf '%s' "$s"
}

if command -v jq >/dev/null 2>&1; then
  ESCAPED=$(printf '%s' "$NEW_MAP_ROLES" | jq -Rs .)
  kubectl patch cm aws-auth -n kube-system --type=merge \
    -p "{\"data\":{\"mapRoles\":${ESCAPED}}}"
else
  ESCAPED=$(json_escape_str "$NEW_MAP_ROLES")
  kubectl patch cm aws-auth -n kube-system --type=merge \
    -p "{\"data\":{\"mapRoles\":\"${ESCAPED}\"}}"
fi

echo ""
echo "✓ aws-auth actualizado."
echo ""
echo "Si algo salió mal, restaurá el backup con:"
echo "  kubectl apply -f $BACKUP_FILE"
