# Ingress

An Ingress is a resource that defines **HTTP/HTTPS routing rules** — which hostname goes to which Service, with optional path-based routing. It's the standard way to expose multiple HTTP services through a single entry point.

---

## Ingress vs Services

Services (NodePort, LoadBalancer) operate at **Layer 4** (TCP/UDP) — they forward raw traffic without inspecting it. Ingress operates at **Layer 7** (HTTP) — it can route based on hostnames, URL paths, and headers.

| Feature | NodePort/LoadBalancer | Ingress |
|---------|----------------------|---------|
| Routing by hostname | No | Yes |
| Routing by URL path | No | Yes |
| TLS termination | No (app handles it) | Yes |
| Multiple services on one IP | No (one port per service) | Yes |
| Protocol | Any TCP/UDP | HTTP/HTTPS only |

Typical production setup: one LoadBalancer Service in front of the Ingress controller, which then routes to many ClusterIP Services internally.

---

## Ingress Controller

An Ingress resource on its own does nothing — it's just a config object. You need an **Ingress controller** that reads these resources and configures the actual reverse proxy.

Common controllers:

| Controller | Notes |
|------------|-------|
| **ingress-nginx** | Was the gold standard, now deprecated |
| **Traefik** | Active, Helm-managed, auto-discovers Ingress resources |
| **HAProxy** | High performance, common in on-prem |
| **Contour** | Envoy-based |

We'll use **Traefik** since ingress-nginx is deprecated.

### Installing Traefik via Helm

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

kubectl create namespace traefik

helm install traefik traefik/traefik \
  --namespace traefik \
  --set service.type=NodePort
```

We set `service.type=NodePort` because we don't have a LoadBalancer controller (no MetalLB). In a cloud environment you'd use the default LoadBalancer type.

Verify the pod is running:

```bash
kubectl get pods -n traefik
```

```
NAME                       READY   STATUS    RESTARTS   AGE
traefik-6bdc67497f-t7b8j   1/1     Running   0          10s
```

---

## Creating an Ingress Resource

Now that the controller is running, let's route traffic to the `web-clusterip` Service from the services section.

Create `web-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: services-test
spec:
  ingressClassName: traefik
  rules:
    - host: web.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-clusterip
                port:
                  number: 80
```

**Breaking down the manifest:**

| Field | Purpose |
|-------|---------|
| `ingressClassName` | Which controller handles this Ingress. Must match an installed IngressClass |
| `rules[].host` | Hostname to match (from the HTTP `Host` header) |
| `rules[].http.paths[].path` | URL path to match |
| `pathType: Prefix` | Match any path starting with `/` (alternatives: `Exact`, `ImplementationSpecific`) |
| `backend.service` | Which Service to forward matching requests to |

Apply:

```bash
kubectl apply -f web-ingress.yaml
```

### Verify

```bash
kubectl -n services-test get ingress
```

```
NAME          CLASS     HOSTS       ADDRESS   PORTS   AGE
web-ingress   traefik   web.local             80      4s
```

Describe for more detail — shows the backend mapping:

```bash
kubectl -n services-test describe ingress web-ingress
```

```
Rules:
  Host        Path  Backends
  ----        ----  --------
  web.local
              /   web-clusterip:80 (10.244.194.75:80)
```

The IP in parentheses is the actual pod IP — Traefik resolves the Service to its endpoints.

---

## Testing the Ingress

The Ingress controller (Traefik) is exposed via a NodePort Service. First, find which port:

```bash
kubectl -n traefik get svc traefik
```

```
NAME      TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
traefik   LoadBalancer   10.104.205.20   <pending>     80:31646/TCP,443:31044/TCP   3m47s
```

Port `31646` is the HTTP NodePort. Use the **node's IP** (not the ClusterIP) to reach it from outside the cluster.

Since we're routing by hostname (`web.local`), the `Host` header must be set. Either add a `/etc/hosts` entry or pass it via curl:

```bash
curl -H "Host: web.local" http://192.168.252.2:31646
```

This returns the nginx welcome page — the full request flow is:

```
curl → node IP:31646 → Traefik (reads Host header) → web-clusterip Service → nginx pod
```

**Why the Host header matters:** Traefik matches incoming requests against Ingress rules using the `Host` header. Without it (or with the wrong value), Traefik doesn't know which backend to route to and returns a 404. This is how multiple services share a single IP — each gets a different hostname.
