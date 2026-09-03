# Network: Service Types

A Service is a stable network identity for pods. Pods themselves are ephemeral — they get deleted and recreated constantly, which changes their hostname and IP. A Service selects pods by label and load-balances traffic across them.

---

## The Four Service Types

| Type | Reachable from | How it works |
|------|---------------|--------------|
| **ClusterIP** | Inside the cluster only | Virtual IP routable only within the cluster. The basic building block — other types build on top of it |
| **NodePort** | Outside the cluster | Opens a port on every node's IP. Traffic to `<nodeIP>:<nodePort>` forwards to the Service |
| **LoadBalancer** | Outside the cluster | Provisions an external load balancer (via cloud provider or MetalLB on-prem). Pods reachable via a single LB IP |
| **ExternalName** | Inside the cluster | The odd one out — a DNS-level CNAME that maps an in-cluster hostname to an external hostname. No proxying, no ClusterIP |

They (except ExternalName) supersede each other in functionality:

```
ClusterIP ⊂ NodePort ⊂ LoadBalancer
```

A NodePort also creates a ClusterIP. A LoadBalancer also creates a NodePort and a ClusterIP. Each type adds a layer of external reachability on top of the previous one.

---

## ClusterIP

The most basic service type — an internal-only virtual IP.

### Setup

Create a namespace and a simple web pod:

```bash
kubectl create namespace services-test
kubectl run web-pod --image=nginx:alpine --labels="app=web" -n services-test
```

Create `web-cluster-ip.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-clusterip
  namespace: services-test
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
```

**What the ports mean:**

| Field | Meaning |
|-------|---------|
| `port` | The port the Service listens on (what clients connect to) |
| `targetPort` | The port on the actual pod (where traffic gets forwarded) |

These don't have to match — you could expose port 8080 on the Service while the pod listens on 80. Here they're both 80 for simplicity.

The `selector: app: web` is how the Service finds its backing pods. Any pod with label `app=web` in the same namespace becomes an endpoint for this Service. If pods are added or removed, the Service updates its endpoint list automatically.

Apply:

```bash
kubectl apply -f web-cluster-ip.yaml
```

### Verify

```bash
kubectl -n services-test get svc
```

```
NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
web-clusterip   ClusterIP   10.105.56.106   <none>        80/TCP    3s
```

The `CLUSTER-IP` (`10.105.56.106`) is a virtual IP assigned from the Service CIDR range (configured at cluster init, separate from the pod CIDR). This IP only exists inside the cluster — it's not bound to any interface. `kube-proxy` programs iptables/IPVS rules on every node so that traffic to this VIP gets redirected to one of the backing pods.

`EXTERNAL-IP` shows `<none>` — ClusterIP Services are not reachable from outside the cluster. This is where NodePort differs.

### Testing

Since ClusterIPs are internal-only, we need to test from inside the cluster:

```bash
kubectl -n services-test run tmp --rm -it --image=busybox --restart=Never -- wget -qO- web-clusterip
```

`web-clusterip` works as a hostname because Kubernetes automatically creates a DNS record for every Service. The full DNS name is `web-clusterip.services-test.svc.cluster.local`, but within the same namespace the short name is enough.

This returns the nginx welcome page — the Service is routing traffic to the pod.
