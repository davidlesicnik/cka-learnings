# Exercise: Kustomize Overlay

## Task

Directory `~/app/base` has a Deployment `api` (1 replica, image `nginx:1.26`). Without editing the base, create an overlay in `~/app/overlays/prod` that:

- Sets namespace `prod`
- Adds name prefix `prod-`
- Scales to 4 replicas
- Changes image tag to `1.27`
- Generates a ConfigMap `api-config` with `LOG_LEVEL=info`

Apply the overlay with `kubectl`.

---

## Setup

```bash
mkdir -p ~/app/base ~/app/overlays/prod

cat > ~/app/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: nginx:1.26
        ports:
        - containerPort: 80
EOF

cat > ~/app/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
EOF

kubectl create namespace prod
```

---

## Reference Solution

Create `~/app/overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod
namePrefix: prod-

resources:
- ../../base

replicas:
- name: api
  count: 4

images:
- name: nginx
  newTag: "1.27"

configMapGenerator:
- name: api-config
  literals:
  - LOG_LEVEL=info
```

Preview before applying:

```bash
kubectl kustomize ~/app/overlays/prod
```

Expected output: ConfigMap + Deployment with `name: prod-api`, `namespace: prod`, `replicas: 4`, `image: nginx:1.27`.

Apply:

```bash
kubectl apply -k ~/app/overlays/prod
```

Verify:

```bash
kubectl get deployment,configmap -n prod
```

---

## Tips

**`kubectl kustomize <dir>` is a dry run.** Always run it first — shows the rendered YAML before anything is applied. Use it to catch mistakes without touching the cluster.

**`resources:` not `bases:`.** `bases:` is deprecated and prints a warning. Use `resources:` to reference the base — same syntax.

**ConfigMap gets a hash suffix automatically.** `api-config` becomes `prod-api-config-hf678c7m2b`. This is by design — Kustomize appends a content hash so pods rolling update when config changes. Don't be alarmed.

**`images:` matches on image name, not container name.** The key is `name: nginx` (the image), not `name: api` (the container). It patches any container using that image.

**`replicas:` field patches by Deployment name.** `name: api` here refers to the Deployment name in the base (before prefix is applied).

**Docs page:** kubernetes.io → "Manage Kubernetes Objects Using Kustomize" — has all fields with examples.

---

## Run Notes

### Run 1 — 9 minutes (with outside help)

Used `kubectl kustomize base/` first to verify the base rendered correctly — good sanity check before touching the overlay.

Used `bases:` instead of `resources:` for the base reference — got a deprecation warning. Fixed to `resources:`.

Needed outside help to get the `kustomization.yaml` fields right (`replicas:`, `images:`, `configMapGenerator:`). These aren't intuitive from first principles — the docs page is the right reference.

`kubectl kustomize .` in the overlay dir confirmed the output looked correct before applying.
