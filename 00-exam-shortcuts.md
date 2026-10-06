# Exam Shortcuts

The exam is ~2 hours with 15+ tasks. `--dry-run=client -o yaml` generates a base manifest without creating anything — pipe to a file, edit, apply. Faster than writing YAML from scratch or copying from docs.

```bash
kubectl <command> --dry-run=client -o yaml > resource.yaml
# edit resource.yaml
kubectl apply -f resource.yaml
```

---

## Quick Reference

| Resource | Command |
|----------|---------|
| Pod | `kubectl run nginx --image=nginx:alpine --dry-run=client -o yaml` |
| Deployment | `kubectl create deployment web --image=nginx:alpine --replicas=3 --dry-run=client -o yaml` |
| Service | `kubectl expose deployment web --port=80 --target-port=80 --dry-run=client -o yaml` |
| Namespace | `kubectl create namespace ns1 --dry-run=client -o yaml` |

---

## Examples

### Pod

```bash
kubectl run nginx --image=nginx:alpine --dry-run=client -o yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: nginx
  name: nginx
spec:
  containers:
  - image: nginx:alpine
    name: nginx
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```

### Kustomize — replicas (not in k8s docs, memorize this)

```yaml
replicas:
  - name: <deployment-name>
    count: <n>
```

### Deployment

```bash
kubectl create deployment web --image=nginx:alpine --replicas=3 --dry-run=client -o yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: web
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - image: nginx:alpine
        name: nginx
        resources: {}
```
