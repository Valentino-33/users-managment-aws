# ──────────────────────────────────────────────────────────────────────────────
# users-managment-aws — Makefile
# ──────────────────────────────────────────────────────────────────────────────

SHELL := /bin/bash
.DEFAULT_GOAL := help

CLUSTER ?= belo-challenge-dev
REGION  ?= us-east-1
ACCOUNT ?= 650790810564

GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m

.PHONY: help
help:  ## Mostrar targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

# ──────────────── IAM (Terraform) ────────────────

.PHONY: iam-init
iam-init:  ## Init del Terraform de IAM
	@if [ ! -f iam/backend.hcl ]; then \
		echo "$(RED)Falta iam/backend.hcl — copialo de backend.hcl.example$(NC)"; exit 1; \
	fi
	cd iam && terraform init -backend-config=backend.hcl

.PHONY: iam-plan
iam-plan:  ## terraform plan de IAM
	cd iam && terraform plan -out=tfplan

.PHONY: iam-apply
iam-apply:  ## Crear los IAM users, groups y roles
	cd iam && terraform apply tfplan

.PHONY: iam-destroy
iam-destroy:  ## Borrar los IAM users, groups y roles (cuidado)
	@printf "$(RED)Esto borra los IAM users e invalida sus access keys.$(NC)\n"
	@read -p "Escribí 'iam' para confirmar: " confirm; \
	if [ "$$confirm" != "iam" ]; then echo "Cancelado."; exit 1; fi
	cd iam && terraform destroy

.PHONY: iam-output
iam-output:  ## Ver outputs (ARNs de roles, etc)
	cd iam && terraform output

# ──────────────── RBAC (manifestos K8s) ────────────────

.PHONY: rbac-apply
rbac-apply: aws-auth-merge clusterroles-apply bindings-apply namespaces-apply env-apply  ## Aplicar todo el RBAC (ClusterRoles + Bindings + Namespaces + Environments)
	@echo "$(GREEN)✓ RBAC aplicado$(NC)"

.PHONY: namespaces-apply
namespaces-apply:  ## Crear los namespaces de aplicación declarados en rbac/environments/dev/
	kubectl create namespace belo-challenge-dev --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace webserver-api01 --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace webserver-api02 --dry-run=client -o yaml | kubectl apply -f -

.PHONY: rbac-migrate
rbac-migrate:  ## Eliminar ClusterRoleBindings cluster-wide del grupo develop (develop-viewer y develop-list-namespaces)
	@printf "$(YELLOW)Eliminando ClusterRoleBinding 'develop-viewer' (acceso cluster-wide al develop group)...$(NC)\n"
	-kubectl delete clusterrolebinding develop-viewer 2>/dev/null || true
	@printf "$(YELLOW)Eliminando ClusterRoleBinding 'develop-list-namespaces' (listing de todos los namespaces)...$(NC)\n"
	-kubectl delete clusterrolebinding develop-list-namespaces 2>/dev/null || true
	@printf "$(GREEN)✓ Listo. Ahora aplicá el nuevo modelo con: make rbac-apply$(NC)\n"

.PHONY: aws-auth-merge
aws-auth-merge:  ## Mergear las nuevas entradas en aws-auth (sin pisar nodos)
	bash ./scripts/merge-aws-auth.sh

.PHONY: clusterroles-apply
clusterroles-apply:  ## Aplicar ClusterRoles (viewer-no-secrets + list-namespaces)
	kubectl apply -f rbac/clusterroles/

.PHONY: bindings-apply
bindings-apply:  ## Aplicar ClusterRoleBindings globales (infra-admin)
	kubectl apply -f rbac/bindings/infra-binding.yaml

.PHONY: env-apply
env-apply:  ## Aplicar RBACDefinitions de todos los ambientes (requiere rbac-manager instalado)
	kubectl apply -f rbac/environments/ --recursive

.PHONY: env-apply-dev
env-apply-dev:  ## Aplicar RBACDefinition del ambiente dev únicamente
	kubectl apply -f rbac/environments/dev/

.PHONY: rbac-manager-install
rbac-manager-install:  ## Instalar el operador rbac-manager vía Helm (solo la primera vez)
	helm repo add fairwinds-stable https://charts.fairwinds.com/stable
	helm repo update
	helm upgrade --install rbac-manager fairwinds-stable/rbac-manager \
	  --namespace rbac-manager --create-namespace --wait

.PHONY: rbac-status
rbac-status:  ## Ver el estado actual de los ClusterRoles, Bindings y aws-auth
	@printf "$(YELLOW)── ClusterRoles ──$(NC)\n"
	@kubectl get clusterrole viewer-no-secrets list-namespaces -o name 2>/dev/null || echo "  (no aplicados)"
	@printf "$(YELLOW)── ClusterRoleBindings (globales) ──$(NC)\n"
	@kubectl get clusterrolebinding infra-admin -o name 2>/dev/null || echo "  (no aplicados)"
	@printf "$(YELLOW)── RoleBindings por ambiente ──$(NC)\n"
	@kubectl get rolebinding develop-viewer --all-namespaces 2>/dev/null || echo "  (ninguno aplicado)"
	@printf "$(YELLOW)── aws-auth (mapRoles) ──$(NC)\n"
	@kubectl get cm aws-auth -n kube-system -o jsonpath='{.data.mapRoles}'

# ──────────────── Verificación ────────────────

.PHONY: verify-developer
verify-developer:  ## Probar acceso como dev-user-01 (requiere ~/.aws/credentials configurado)
	@printf "$(YELLOW)→ Configurando contexto kubectl como developer...$(NC)\n"
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION) \
	  --profile dev-user-01 \
	  --role-arn arn:aws:iam::$(ACCOUNT):role/$(CLUSTER)-eks-developer \
	  --alias verify-dev
	@echo ""
	@printf "$(YELLOW)→ kubectl get namespaces (✗ debe decir Forbidden — los devs no listan todos los namespaces)$(NC)\n"
	-kubectl --context verify-dev get namespaces 2>&1 | head -3
	@echo ""
	@printf "$(YELLOW)→ kubectl get namespace $(CLUSTER) (✓ debe funcionar — GET singular vía RoleBinding de rbac-manager)$(NC)\n"
	-kubectl --context verify-dev get namespace $(CLUSTER) 2>&1 | head -3
	@echo ""
	@printf "$(YELLOW)→ kubectl get pods -n $(CLUSTER) (✓ debe funcionar — RoleBinding en namespace de app)$(NC)\n"
	-kubectl --context verify-dev get pods -n $(CLUSTER) 2>&1 | head -5
	@echo ""
	@printf "$(YELLOW)→ kubectl get pods -n kube-system (✗ debe decir Forbidden)$(NC)\n"
	-kubectl --context verify-dev get pods -n kube-system 2>&1 | head -3
	@echo ""
	@printf "$(YELLOW)→ kubectl get secrets -n $(CLUSTER) (✗ debe decir Forbidden)$(NC)\n"
	-kubectl --context verify-dev get secrets -n $(CLUSTER) 2>&1 | head -3

.PHONY: verify-infra
verify-infra:  ## Probar acceso como infra-user-01
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION) \
	  --profile infra-user-01 \
	  --role-arn arn:aws:iam::$(ACCOUNT):role/$(CLUSTER)-eks-infra \
	  --alias verify-infra
	@printf "$(YELLOW)→ kubectl get nodes (debería funcionar)$(NC)\n"
	kubectl --context verify-infra get nodes
	@printf "$(YELLOW)→ kubectl get secrets -A (debería funcionar)$(NC)\n"
	kubectl --context verify-infra get secrets -A | head -5

.PHONY: get-credentials
get-credentials:  ## Mostrar las credenciales de los users (las muestra UNA SOLA VEZ después de iam-apply)
	@printf "$(RED)Las access keys solo se ven una vez. Guardalas en un password manager.$(NC)\n"
	@cd iam && terraform output -json access_keys | \
	  if command -v jq >/dev/null 2>&1; then jq; \
	  elif command -v python3 >/dev/null 2>&1; then python3 -m json.tool; \
	  elif command -v python >/dev/null 2>&1; then python -m json.tool; \
	  else cat; fi

# ──────────────── Misc ────────────────

.PHONY: clean
clean:  ## Limpiar archivos temporales
	find . -name 'tfplan' -delete
	find . -name '.terraform.lock.hcl' -delete
