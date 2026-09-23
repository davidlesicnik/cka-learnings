# Gateway API

Gateway API is the successor to Ingress — same core job (route HTTP/S traffic to services), but split into separate objects instead of a single monolithic `Ingress` resource.

## Ingress vs Gateway API

The key problem with Ingress: it mashed infrastructure config (what port/protocol to listen on) and application routing (which paths go where) into a single object. This forced app teams and infra teams to share ownership of one resource.

Gateway API separates these concerns into a clear ownership hierarchy:

| Object | Scope | Owned by | Purpose |
|--------|-------|----------|---------|
| `GatewayClass` | Cluster | Platform team | Defines which controller implements this class |
| `Gateway` | Namespace | Infra/SRE | Defines listeners: port, protocol, hostname |
| `HTTPRoute` | Namespace | App dev team | Defines routing rules: paths → services |

App teams create HTTPRoutes and attach them to a Gateway they don't own or manage. Infra teams control the Gateway without touching application routing. This is why Gateway API was created.

---

## Setup

Gateway API CRDs are not bundled with Kubernetes (unlike Ingress) — they're maintained out-of-tree and must be installed separately:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
```

Enable Gateway API support in Traefik:

```bash
helm upgrade traefik traefik/traefik -n traefik --set providers.kubernetesGateway.enabled=true
```

---

## Creating the Three Objects

Create `gatewayclass.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: traefik
spec:
  controllerName: traefik.io/gateway-controller
```

`controllerName` is how the GatewayClass binds to a specific controller. Multiple controllers can coexist in the same cluster — each manages only GatewayClasses with their `controllerName`.

Create `gateway.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
  namespace: default
spec:
  gatewayClassName: traefik
  listeners:
    - name: http
      protocol: HTTP
      port: 8000
```

Create `httproute.yaml` (reusing the `web-clusterip` service from the [Ingress](09-ingress.md) section):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: default
spec:
  parentRefs:
    - name: web-gateway
  hostnames:
    - "web.local"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web-clusterip
          port: 80
```

`parentRefs` is how an HTTPRoute attaches to a Gateway — the route declares which Gateway it belongs to, rather than the Gateway having to list all its routes.

```bash
kubectl apply -f gatewayclass.yaml
kubectl apply -f gateway.yaml
kubectl apply -f httproute.yaml
```

### Verify

```bash
kubectl get gatewayclass,gateway,httproute
```

```
NAME                                             CONTROLLER                      ACCEPTED   AGE
gatewayclass.gateway.networking.k8s.io/traefik   traefik.io/gateway-controller   True       3m9s

NAME                                            CLASS     ADDRESS   PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/web-gateway   traefik             False        25s

NAME                                            HOSTNAMES       AGE
httproute.gateway.networking.k8s.io/web-route   ["web.local"]   25s
```

```bash
kubectl describe httproute web-route
```

```
Hostnames:
    web.local

Rules:
    Backend Refs:
      Kind:    Service
      Name:    web-clusterip
      Port:    80
      Weight:  1
```

---

## Testing

Get the Traefik NodePort and a node IP:

```bash
kubectl get nodes -o wide
```

```
NAME          STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP
k8s-cp1       Ready    control-plane   34d   v1.36.3   192.168.252.2   <none>
k8s-worker1   Ready    <none>          34d   v1.36.3   192.168.252.3   <none>
k8s-worker2   Ready    <none>          34d   v1.36.3   192.168.252.4   <none>
```

```bash
kubectl -n traefik get svc traefik
```

```
NAME      TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
traefik   LoadBalancer   10.104.205.20   <pending>     80:31646/TCP,443:31044/TCP   11d
```

Curl with the `Host` header to simulate a real DNS request — same pattern as Ingress:

```bash
curl -H "Host: web.local" http://192.168.252.2:31646
```

```html
<!DOCTYPE html>
<html>
...
<h1>Welcome to nginx!</h1>
...
</html>
```

Traefik matched the `Host: web.local` header, looked up the HTTPRoute, and forwarded to `web-clusterip:80`.
