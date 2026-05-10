# OIDC — preparado, no activado

Esta carpeta tiene todo lo necesario para integrar el cluster con un
proveedor OIDC externo (Cognito, Okta, Auth0, Keycloak, Google) cuando se
quiera dejar atrás los IAM users como mecanismo de autenticación humana.

**Hoy no está activado** porque la autenticación de la demo va por IAM
roles (ver el [README principal](../README.md)). Esta carpeta es la receta
para activarlo a futuro sin tener que repensar desde cero.

> **Importante para no confundirse:** este OIDC es **distinto** del OIDC que
> ya está activado para IRSA (IAM Roles for Service Accounts, usado por
> Karpenter, ALB Controller, EBS CSI driver, External DNS, etc.). Aquel OIDC
> es **del cluster hacia AWS** — autoriza a las pods a hablar con APIs AWS.
> Este OIDC es **al revés** — autoriza a usuarios humanos a hablar con la
> API del cluster usando tokens de un IDP externo.

## Cuándo activarlo

- Cuando hay >5 usuarios humanos y la gestión de access keys IAM se vuelve
  tedioso o riesgoso.
- Cuando la empresa ya usa SSO (Google Workspace, Okta, AzureAD) y queremos
  que el cluster valide contra esa identidad.
- Cuando se necesita MFA obligatorio (los IAM access keys no soportan MFA
  para llamadas de API; el flujo OIDC sí).
- Cuando se quiere desentenderse de las access keys y rotar credenciales
  vía sesión OIDC (típicamente 8-12 horas).

## Cómo se activa (paso a paso)

### 1. Configurar la app en el IDP

Variables que vas a obtener de tu IDP. Las anotás antes de seguir:

| Variable | De dónde sale |
|---|---|
| `issuer_url` | URL del IDP. Ej `https://login.microsoftonline.com/<tenant>/v2.0` o `https://accounts.google.com` |
| `client_id` | El ID de la app que registrás en el IDP (en Okta/Auth0 lo llaman "Application ID") |
| `groups_claim` | Nombre del claim en el ID token que lleva los grupos. Suele ser `groups` |
| `username_claim` | Claim para identificar al usuario. Suele ser `email` o `sub` |

En el IDP, configurar:
- Tipo de aplicación: **Native / Public** (kubectl es un cliente CLI sin secret)
- Redirect URI: `http://localhost:8000` y `http://localhost:18000` (los puertos que usa kubelogin / oidc-login plugin)
- Que el ID token incluya los claims `groups` y `email`
- Crear los grupos que vamos a mapear: `develop` e `Infra`. Asignar usuarios a esos grupos.

### 2. Asociar el OIDC provider al cluster

Editá `cluster-config.tf.disabled` con tus valores reales:

```hcl
issuer_url       = "https://accounts.google.com"
client_id        = "1234567890-abc.apps.googleusercontent.com"
username_claim   = "email"
username_prefix  = "oidc:"
groups_claim     = "groups"
groups_prefix    = "oidc:"
```

Renombralo a `cluster-config.tf` y aplicalo:

```bash
mv oidc/cluster-config.tf.disabled iam/cluster-config.tf
cd iam && terraform plan && terraform apply
```

EKS demora **5-10 minutos** en activar el provider config. Mientras tanto,
los logs de IAM no pasan por OIDC.

### 3. Activar los bindings con prefijo `oidc:`

Cuando OIDC mapea grupos al cluster, los antepone con el prefix definido
(`oidc:` en el ejemplo). Por eso necesitamos bindings paralelos a los de IAM:

```bash
mv oidc/bindings-oidc/develop-binding.yaml.disabled rbac/bindings/develop-binding-oidc.yaml
mv oidc/bindings-oidc/infra-binding.yaml.disabled   rbac/bindings/infra-binding-oidc.yaml
kubectl apply -f rbac/bindings/develop-binding-oidc.yaml
kubectl apply -f rbac/bindings/infra-binding-oidc.yaml
```

A partir de acá, el cluster acepta autenticación por **dos vías en paralelo**:
- IAM roles (los developers/infra que ya estaban) — sigue funcionando.
- OIDC tokens (usuarios federados) — nueva vía.

Esto es lo que querés durante la transición. Después podés deshabilitar IAM
borrando las entradas correspondientes del aws-auth.

### 4. Configurar kubectl en cada usuario

Cada usuario instala el plugin de OIDC para kubectl:

```bash
# kubelogin (recomendado, el oficial-de-facto)
brew install int128/kubelogin/kubelogin
# O en Linux:
# https://github.com/int128/kubelogin/releases
```

Y configura su kubeconfig:

```bash
kubectl config set-credentials oidc-user \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url=https://accounts.google.com \
  --exec-arg=--oidc-client-id=<TU-CLIENT-ID>
```

Cuando hace `kubectl get pods`, kubelogin abre el navegador, el usuario se
loguea en su IDP, y kubectl recibe el token. El token vale 1 hora; cuando
expira, kubelogin lo refresca silenciosamente.

## Cómo conviven IAM y OIDC

Mientras los dos estén activos, el cluster autentica a quien primero acepte
el token. En la práctica:

- Si el usuario tiene credenciales IAM configuradas en `~/.aws/credentials`
  y kubeconfig con `aws-iam-authenticator`, va por IAM.
- Si tiene kubeconfig con kubelogin/oidc-login, va por OIDC.

No hay conflicto — son dos exec plugins distintos detectados por kubectl.

## Cuándo apagar IAM

Cuando todos los humanos estén migrados a OIDC, podés:

1. Borrar las entradas de los roles developer e infra del aws-auth.
2. (opcional) Borrar los IAM users del Terraform.
3. Dejar el aws-auth solo con los node roles (que **no se tocan**).

## Costos

- AWS no cobra por habilitar OIDC en EKS — está incluido.
- El IDP puede o no cobrar (Google Workspace y AzureAD vienen con SSO; Okta y
  Auth0 cobran por usuario activo si pasás cierto threshold).
