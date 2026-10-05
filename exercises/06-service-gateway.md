# Exercise: Fix Broken Service + Gateway API HTTPRoute

## Task

A Deployment `web` with 3 replicas exists, but the Service in front of it has no endpoints. Find and fix the problem. Then expose it with an HTTPRoute via Gateway API so `web.example.com/app` routes to the Service on port 80.

---

## Setup

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: default
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
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: default
spec:
  selector:
    app: web-app   # bug: doesn't match pod label app=web
  ports:
  - port: 80
    targetPort: 80
```

---

## Reference Solution

### Part 1: Fix the Service

Diagnostic flow — empty endpoints is the entry point:

```bash
kubectl get endpointslice
# web-xxxxx shows ENDPOINTS: <none>

kubectl describe svc web
# Selector: app=web-app  ← wrong

kubectl get pods --show-labels
# Labels: app=web  ← actual pod label
```

Fix — edit the service selector:

```bash
kubectl edit svc web
# change selector.app: web-app → web
```

Verify endpoints populated:

```bash
kubectl get endpointslice
# web-xxxxx shows 3 pod IPs
```

### Part 2: HTTPRoute

Assumes GatewayClass and Gateway already exist. Docs page: **Gateway API** on kubernetes.io has an HTTPRoute example.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-httproute
spec:
  parentRefs:
  - name: web-gateway
  hostnames:
  - "web.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /app
    backendRefs:
    - name: web
      port: 80
```

```bash
kubectl apply -f httproute.yaml
kubectl get httproute web-httproute
```

Verify routing works:

```bash
curl -H "Host: web.example.com" http://<node-ip>:<traefik-nodeport>/app
```

---

## Tips

**Empty endpoints = selector mismatch (usually).** The diagnostic path is always: `endpointslice` → `describe svc` (check Selector) → `get pods --show-labels` (check actual labels). One of those three steps will show the mismatch.

**Service selector vs Deployment selector — not the same thing.** The Deployment selector (`spec.selector.matchLabels`) controls which pods the Deployment owns. The Service selector (`spec.selector`) controls which pods receive traffic. They often match but are completely independent. A Service with a wrong selector doesn't affect the Deployment at all — pods run fine, traffic just never reaches them.

**`kubectl edit svc` is the fastest fix** for a selector mismatch — one field change, no manifest file needed.

**HTTPRoute `parentRefs` is how it attaches to a Gateway.** Unlike Ingress (which uses `ingressClassName`), an HTTPRoute declares which Gateway it belongs to. If the Gateway doesn't exist or the name is wrong, the route won't be programmed — check `kubectl describe httproute` for status conditions.

---

## Run Notes

### Run 1 — Part 1: 3m18s, Part 2: 1m15s

Part 1: Found empty endpointslice → described service → saw `Selector: app=web-app` → described a pod → saw `Labels: app=web` → edited service. Clean diagnostic path.

Part 2: Found Gateway API docs page, found HTTPRoute example, modified names and path. Fast because the structure was familiar from the main notes.
