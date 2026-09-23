# Helm and Kustomize

Two different approaches to managing Kubernetes manifests at scale:

| | Helm | Kustomize |
|--|------|-----------|
| **Approach** | Full package manager with Go `{{ }}` templating | Plain YAML overlays on top of base manifests |
| **Install** | External binary required | Built into `kubectl` (`kubectl apply -k`) |
| **Versioning** | Tracks releases with full history and rollback | No built-in release tracking |
| **Best for** | Third-party software (Traefik, Prometheus, etc.) | Your own app manifests across environments |

Neither replaces the other — they solve different problems. Helm manages external packages; Kustomize patches your own manifests per environment (dev/staging/prod).

---

## Helm

Helm's key concepts:

- **Chart** — the package: templates + default values
- **Release** — a deployed instance of a chart, tracked by name and namespace
- **Values** — configuration that overrides chart defaults at install/upgrade time
- **Repository** — a registry of charts (like `traefik/traefik`)

### Templating

Helm chart templates are YAML files with Go template placeholders. When you run `helm install` or `helm upgrade`, Helm renders the templates by substituting values, then applies the resulting plain YAML to the cluster.

A template file looks like this:

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-app
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

The corresponding `values.yaml` (chart defaults):

```yaml
replicaCount: 2
image:
  repository: nginx
  tag: alpine
```

At install time, `{{ .Values.replicaCount }}` is replaced with `2`, `{{ .Release.Name }}` with whatever you named the release. You override defaults by passing `--set key=value` or a custom `--values myvalues.yaml`.

Common template variables:

| Variable | What it contains |
|----------|-----------------|
| `.Values.*` | Values from `values.yaml`, overrideable at install |
| `.Release.Name` | The release name (`helm install <name>`) |
| `.Release.Namespace` | Namespace the release is deployed into |
| `.Chart.Name` | Chart name from `Chart.yaml` |
| `.Chart.Version` | Chart version |

Preview the rendered output without applying:

```bash
helm template traefik traefik/traefik -n traefik --set service.type=NodePort
```

This is useful for inspecting what Helm will actually send to the cluster before committing.

---

### Inspecting an existing release

Traefik was already installed via Helm. Check all releases across namespaces:

```bash
helm list -A
```

```
NAME    NAMESPACE       REVISION        UPDATED                                         STATUS       CHART           APP VERSION
traefik traefik         1               2026-09-11 14:34:36.216112833 +0200 CEST        deployed     traefik-41.5.0  v3.7.13
```

Check what values were overridden from chart defaults:

```bash
helm get values traefik -n traefik
```

```
USER-SUPPLIED VALUES:
service:
  type: NodePort
```

Only user-supplied overrides are shown. Add `--all` to see the full merged values including chart defaults.

### Upgrade, history, and rollback

Upgrade the release (re-supplying our value override):

```bash
helm upgrade traefik traefik/traefik -n traefik --set service.type=NodePort
```

```
Release "traefik" has been upgraded. Happy Helming!
NAME: traefik
LAST DEPLOYED: Wed Sep 23 09:58:22 2026
NAMESPACE: traefik
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
```

Each install or upgrade increments the revision number. View full history:

```bash
helm history traefik -n traefik
```

```
REVISION        UPDATED                         STATUS          CHART           APP VERSION DESCRIPTION
1               Fri Sep 11 14:34:36 2026        superseded      traefik-41.5.0  v3.7.13     Install complete
2               Wed Sep 23 09:58:22 2026        deployed        traefik-41.5.0  v3.7.13     Upgrade complete
```

Roll back to a specific revision:

```bash
helm rollback traefik 1 -n traefik
```

```
Rollback was a success! Happy Helming!
```

Helm stores the full state of each revision, so a rollback restores the exact previous configuration — not just values, but the entire rendered manifest set.

---

## Kustomize

Instead of templates, Kustomize uses a **base** (plain manifests) and **overlays** (patches that modify the base per environment). The base never changes — only the overlay patch differs between environments.

```
kustomize-demo/
├── base/
│   ├── deployment.yaml
│   └── kustomization.yaml
└── overlays/
    └── prod/
        └── kustomization.yaml
```

### Base

```bash
mkdir -p ~/kustomize-demo/base
```

Create `~/kustomize-demo/base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kustomize-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kustomize-demo
  template:
    metadata:
      labels:
        app: kustomize-demo
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
```

Create `~/kustomize-demo/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
```

The `kustomization.yaml` is the entry point — it lists which resources belong to this layer.

### Overlay

```bash
mkdir -p ~/kustomize-demo/overlays/prod
```

Create `~/kustomize-demo/overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: Deployment
      name: kustomize-demo
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 5
```

The patch uses JSON Patch format: `op` is the operation (`replace`, `add`, `remove`), `path` is the YAML field path, `value` is the new value. This changes replicas to 5 for prod without touching the base manifest.

Preview what will be applied before committing:

```bash
kubectl kustomize ~/kustomize-demo/overlays/prod
```

Apply it:

```bash
kubectl apply -k ~/kustomize-demo/overlays/prod
```

The base deployment has 2 replicas. The prod overlay patches it to 5. A staging overlay could patch it to 1. The base stays unchanged throughout.
