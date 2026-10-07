# Exercise: Ingress

## Task

Namespace `web` has two services already running: `svc-blue` and `svc-green`, both on port 80.

1. Create an `Ingress` named `web-ingress` in namespace `web` that routes:
   - `web.local/blue` → `svc-blue:80`
   - `web.local/green` → `svc-green:80`
   - Use `pathType: Prefix`

2. Verify routing with `curl` (via a test pod or the ingress controller IP).

3. Write the ingress class name used by the ingress controller to `/opt/answers/q17.txt`.

---

## Setup

```bash
kubectl create namespace web

kubectl create deployment blue -n web --image=nginx --port=80
kubectl create deployment green -n web --image=nginx --port=80
kubectl expose deployment blue -n web --name=svc-blue --port=80
kubectl expose deployment green -n web --name=svc-green --port=80

# Check what ingress class is available
kubectl get ingressclass
```

---

## Reference Solution

```bash
# 1. Check available ingress class
kubectl get ingressclass
# e.g. "nginx" or "traefik"

# Create Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: web
spec:
  ingressClassName: nginx
  rules:
    - host: web.local
      http:
        paths:
          - path: /blue
            pathType: Prefix
            backend:
              service:
                name: svc-blue
                port:
                  number: 80
          - path: /green
            pathType: Prefix
            backend:
              service:
                name: svc-green
                port:
                  number: 80
EOF

# 2. Verify
kubectl get ingress -n web
kubectl describe ingress web-ingress -n web

# Test (if ingress controller has a NodePort or LB IP):
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H "Host: web.local" http://$INGRESS_IP/blue
curl -H "Host: web.local" http://$INGRESS_IP/green

# 3. Write ingress class
kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}' > /opt/answers/q17.txt
```

---

## Tips

**`ingressClassName` field replaces `kubernetes.io/ingress.class` annotation** (deprecated since 1.18). Use the field, not the annotation.

**`kubectl get ingressclass`** — always check what's available before writing the manifest. Exam will have one installed.

**`pathType: Prefix` vs `Exact`:** `Prefix` matches `/blue` and `/blue/anything`. `Exact` matches only `/blue`. Use `Prefix` unless told otherwise.

**Host header required for routing.** Without `curl -H "Host: web.local"`, the ingress won't match the rule. In a browser, set `/etc/hosts`.

**`describe ingress` shows the backend rules** and whether endpoints are populated. If Address is empty, the ingress controller isn't running or isn't watching the namespace.

**Default backend:** If no rule matches, traffic goes to `spec.defaultBackend`. If not set, ingress controller returns 404.

**Ingress vs Gateway API:** Ingress is `networking.k8s.io/v1` — single resource, controller-specific annotations. Gateway API splits across `GatewayClass`, `Gateway`, `HTTPRoute` — more expressive. Both are on the exam.

---

## Run Notes

### Run 1 — 6m30s

`kubectl create ingress --help` has a usable example — follow that.

`kubectl get ingress` doesn't show the IP directly — had to find the Traefik service IP separately (`kubectl get svc -n traefik`).

Needed outside help for the `curl -H "Host: web.local"` pattern — not obvious that you need to fake the Host header when testing via node IP.
