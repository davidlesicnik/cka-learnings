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

## NodePort

NodePort builds on ClusterIP by forwarding a port on every node's IP to the Service. The Service becomes reachable from outside the cluster — anything that can reach a node's IP can reach the Service.

### Setup

Create `web-nodeport.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
  namespace: services-test
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30000
```

**The three ports in a NodePort Service:**

| Field | Meaning |
|-------|---------|
| `port` | The ClusterIP port (internal access, same as before) |
| `targetPort` | The port on the pod |
| `nodePort` | The port opened on every node's external IP (must be in range 30000-32767) |

The `nodePort` range (30000-32767) is a Kubernetes default. It's deliberately high to avoid colliding with well-known ports. If you omit `nodePort`, Kubernetes assigns a random one from this range.

Apply:

```bash
kubectl apply -f web-nodeport.yaml
```

### Verify

```bash
kubectl -n services-test get svc
```

```
NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
web-clusterip   ClusterIP   10.105.56.106   <none>        80/TCP         8d
web-nodeport    NodePort    10.110.18.243   <none>        80:30000/TCP   3s
```

`80:30000/TCP` shows the mapping — internal port 80 is forwarded to node port 30000. Note that the NodePort Service also gets its own ClusterIP (`10.110.18.243`) — it's still a ClusterIP under the hood, with the node port as an additional entry point.

`EXTERNAL-IP` is still `<none>` — NodePort doesn't provision an external IP. You access it via the node's existing IP directly.

### Testing from outside the cluster

The Service is now reachable via any node's IP on port 30000 — even nodes that aren't running the pod. `kube-proxy` handles forwarding across nodes.

```bash
curl 192.168.252.2:30000
```

This returns the nginx welcome page from the host machine (outside the cluster).

**Why NodePort works on all nodes:** `kube-proxy` programs iptables rules on every node to catch traffic on the `nodePort` and redirect it to one of the Service's backing pods, regardless of which node the pod is on. This means any node can serve as an entry point.

## LoadBalancer

LoadBalancer is the top of the Service hierarchy — it creates a ClusterIP, a NodePort, and then asks an external controller to provision a load balancer with a dedicated IP.

> **Note:** This section is partially theoretical. Without a load balancer controller (like MetalLB for bare-metal or a cloud provider integration), the Service works but never gets an external IP.

### How it works in practice

In a **cloud environment** (AWS, GCP, Azure), creating a LoadBalancer Service triggers the cloud controller to:
1. Provision an actual load balancer (e.g. an AWS NLB/ALB)
2. Assign it a public/private IP
3. Configure it to forward traffic to the NodePort on each node
4. Write that IP back into the Service's `EXTERNAL-IP` field

On **bare-metal** clusters, nothing does this automatically. You need to install a controller like **MetalLB**, which watches for LoadBalancer Services and assigns IPs from a configured pool on your local network.

### Setup

Create `web-loadbalancer.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-loadbalancer
  namespace: services-test
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
```

Notice there's no `nodePort` — Kubernetes auto-assigns one (since LoadBalancer includes NodePort).

```bash
kubectl apply -f web-loadbalancer.yaml
```

### Verify

```bash
kubectl -n services-test get svc
```

```
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
web-clusterip      ClusterIP      10.105.56.106   <none>        80/TCP         8d
web-loadbalancer   LoadBalancer   10.104.56.214   <pending>     80:30639/TCP   48s
web-nodeport       NodePort       10.110.18.243   <none>        80:30000/TCP   5m54s
```

`EXTERNAL-IP` is stuck at `<pending>` — this is expected. No controller is installed to fulfill the LoadBalancer request. It will stay in this state indefinitely until one is installed.
In a cloud cluster, this would show the load balancer's IP after a few seconds.

`80:30639/TCP` shows that a NodePort (30639) was auto-assigned. Since LoadBalancer is a superset of NodePort, the Service is still reachable via any node's IP on that port:

```bash
curl 192.168.252.2:30639
```

This works — even without an external LB, the NodePort and ClusterIP layers are fully functional.

## ExternalName

The odd one out. ExternalName doesn't proxy traffic or assign a ClusterIP — it's purely a **DNS-level CNAME redirect**.
When a pod resolves the Service name, CoreDNS returns the external hostname instead of a cluster IP. The pod then connects directly to the external endpoint.

**How it differs from other Service types:**

- No `selector` — it doesn't target any pods
- No ClusterIP — no `kube-proxy` rules, no iptables
- No port forwarding — DNS only
- The pod connects directly to the external target after DNS resolution

### Setup

Create `external-db.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
  namespace: services-test
spec:
  type: ExternalName
  externalName: db.example.com
```

```bash
kubectl apply -f external-db.yaml
```

### Verify

```bash
kubectl -n services-test get svc
```

```
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
external-db        ExternalName   <none>          db.example.com   <none>         7s
web-clusterip      ClusterIP      10.105.56.106   <none>           80/TCP         8d
web-loadbalancer   LoadBalancer   10.104.56.214   <pending>        80:30639/TCP   10m
web-nodeport       NodePort       10.110.18.243   <none>           80:30000/TCP   15m
```

Notice: `CLUSTER-IP` is `<none>` and `PORT(S)` is `<none>` — this Service only exists as a DNS entry, nothing more.

### Testing with nslookup

```bash
kubectl -n services-test run tmp --rm -it --image=busybox --restart=Never -- nslookup external-db
```

The relevant output (trimmed — nslookup tries several search domains first, producing NXDOMAIN noise before finding the match):

```
external-db.services-test.svc.cluster.local     canonical name = db.example.com
```

CoreDNS returns a CNAME record pointing `external-db.services-test.svc.cluster.local` → `db.example.com`. Any pod in the `services-test` namespace can now use `external-db` as a hostname, and DNS resolves it to the external address.

**About the NXDOMAIN noise:** `nslookup` tries the search domains from `/etc/resolv.conf` in order (`svc.cluster.local`, `cluster.local`, your host domain). Most fail before hitting `services-test.svc.cluster.local` which is the correct FQDN. This is normal behavior.

### When ExternalName is useful

- **Environment abstraction** — your app connects to `db` (a Service name). In dev, it's an ExternalName pointing to a dev database. In prod, it's a ClusterIP pointing to an in-cluster database. Same app config, different Service definition per environment.
- **Migration** — moving a service into the cluster gradually. Start with ExternalName pointing to the old external host, then switch to a ClusterIP when the in-cluster version is ready.
- **Readable aliases** — `payment-gateway` is easier to remember than `api.payments.vendor.example.com`
