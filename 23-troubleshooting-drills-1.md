# Troubleshooting Drills — Part 1

Structured break-and-fix scenarios. Each follows the same pattern: introduce the fault, identify it, fix it.

General first-pass diagnostic workflow:
1. `kubectl get pods` — what's the status?
2. `kubectl describe pod <name>` — check Events at the bottom
3. `kubectl logs <name>` — check application output (if the container started)
4. `journalctl -u kubelet` — node-level issues (if the pod never started)

---

## Drill 1: Bad Image Name / Tag

### Setup

Create `bad-image-demo.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-image-demo
spec:
  containers:
    - name: app
      image: nginx:this-tag-does-not-exist
```

```bash
kubectl apply -f bad-image-demo.yaml
```

### Symptoms

```bash
kubectl get pods
```

```
NAME             READY   STATUS         RESTARTS   AGE
bad-image-demo   0/1     ErrImagePull   0          10s
```

After a minute or two it transitions to `ImagePullBackOff` — Kubernetes backs off exponentially between retries rather than hammering the registry. `ErrImagePull` = active pull attempt failed; `ImagePullBackOff` = waiting before the next attempt.

### Diagnosis

```bash
kubectl describe pod bad-image-demo
```

```
Events:
  Warning  Failed     14s (x2 over 29s)  kubelet  Failed to pull image "nginx:this-tag-does-not-exist": not found
  Warning  Failed     14s (x2 over 29s)  kubelet  Error: ErrImagePull
  Normal   BackOff    3s (x2 over 28s)   kubelet  Back-off pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     3s (x2 over 28s)   kubelet  Error: ImagePullBackOff
```

Events make it clear: the tag doesn't exist on the registry.

### Fix

Correct the image tag in the manifest and re-apply.

---

## Drill 2: Service Unreachable (Selector Mismatch)

### Setup

Create `broken-svc-demo.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broken-svc-demo
  labels:
    app: broken-svc-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: broken-svc-demo
  template:
    metadata:
      labels:
        app: broken-svc-demo
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
---
apiVersion: v1
kind: Service
metadata:
  name: broken-svc
spec:
  selector:
    app: wrong-label
  ports:
    - port: 80
      targetPort: 80
```

The service selector (`app: wrong-label`) doesn't match the deployment's pod labels (`app: broken-svc-demo`).

```bash
kubectl apply -f broken-svc-demo.yaml
```

### Symptoms

```bash
kubectl run tmp --rm -it --image=busybox --restart=Never -- wget -qT 3 -O- broken-svc
```

```
wget: can't connect to remote host (10.102.86.37): Connection refused
```

### Diagnosis

```bash
kubectl describe svc broken-svc
```

```
Selector:    app=wrong-label
Endpoints:
```

Empty `Endpoints` is the key signal — the service exists but has no pods to route to. You can also check directly:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=broken-svc
```

```
NAME               ADDRESSTYPE   PORTS   ENDPOINTS   AGE
broken-svc-xxxxx   IPv4          80      <none>      2m
```

Compare against the deployment's labels:

```bash
kubectl describe deploy broken-svc-demo | grep Labels
```

```
Labels:  app=broken-svc-demo
```

`app=wrong-label` vs `app=broken-svc-demo` — mismatch confirmed.

### Fix

Edit the service selector to match the pod labels:

```yaml
spec:
  selector:
    app: broken-svc-demo
```

Once applied, `kubectl get endpoints broken-svc` should show pod IPs.
