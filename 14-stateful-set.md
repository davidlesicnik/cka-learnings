# StatefulSets

StatefulSets (sts) exist for workloads that need a **stable identity** across pod restarts. Unlike Deployment pods (which get random hash suffixes), StatefulSet pods get sequential names (`web-0`, `web-1`, `web-2`), and each pod keeps its identity, hostname, and storage even if rescheduled or deleted and recreated.

This matters for services where specific instances are important — not "just any replica" — like databases, etcd, or ZooKeeper.

---

## StatefulSet Guarantees

| Guarantee | What it means |
|-----------|---------------|
| **Stable, unique pod names** | Sequential suffixes (`-0`, `-1`, `-2`), not random hashes. Pod name = stable identity |
| **Ordered sequential scaling** | Pods start one by one: `-0` first, then `-1`, then `-2`. Each pod must be Running before the next starts. Scale-down is reverse order. |
| **Stable per-pod storage** | Each pod gets its own PVC via `volumeClaimTemplates`. The PVC follows the pod — if `web-0` is deleted and recreated, it reattaches to the same PVC |

## StatefulSet vs Deployment

| | Deployment | StatefulSet |
|---|-----------|-------------|
| Pod names | `rollout-demo-d79786d47-x8k2p` (random) | `web-0`, `web-1`, `web-2` (sequential) |
| Pod ordering | All created/deleted in parallel | Created sequentially, deleted in reverse |
| Storage | All pods share a PVC (or each gets an ephemeral one) | Each pod gets a dedicated PVC that persists |
| DNS | Single Service ClusterIP load-balances | Headless Service gives each pod its own DNS record |
| Use case | Stateless apps (web servers, APIs) | Stateful apps (databases, caches, message queues) |

---

## Headless Service

StatefulSets require a **headless Service** (`clusterIP: None`). Instead of a single virtual IP that load-balances, it creates individual DNS records for each pod:

```
web-0.web-headless.default.svc.cluster.local
web-1.web-headless.default.svc.cluster.local
web-2.web-headless.default.svc.cluster.local
```

This lets clients address specific pods by name — critical for stateful workloads where you need to talk to a particular instance (e.g. the primary database replica, not a random one).

---

## Creating a StatefulSet

Two manifests needed: the headless Service and the StatefulSet.

Create `web-headless-svc.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-headless
spec:
  clusterIP: None
  selector:
    app: web-sts
  ports:
    - port: 80
```

Create `web-sts.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: web-headless
  replicas: 3
  selector:
    matchLabels:
      app: web-sts
  template:
    metadata:
      labels:
        app: web-sts
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
  volumeClaimTemplates:
    - metadata:
        name: www
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-path
        resources:
          requests:
            storage: 1Gi
```

**Key fields:**

| Field | Purpose |
|-------|---------|
| `serviceName` | Must match the headless Service name — this is what wires DNS together |
| `volumeClaimTemplates` | Creates a separate PVC **per pod** (e.g. `www-web-0`, `www-web-1`, `www-web-2`). This is the big difference from a Deployment's `volumes`, which references a single shared PVC by name |

```bash
kubectl apply -f web-headless-svc.yaml
kubectl apply -f web-sts.yaml
```

### Verify

```bash
kubectl get pods
```

```
NAME                           READY   STATUS    RESTARTS      AGE
web-0                          1/1     Running   0             63s
web-1                          1/1     Running   0             59s
web-2                          1/1     Running   0             54s
```

Three pods with sequential suffixes. Notice the age difference — each pod was created after the previous one became Ready (ordered startup).

### Stable identity survives deletion

```bash
kubectl delete pod web-0
kubectl get pods
```

```
NAME                           READY   STATUS    RESTARTS      AGE
web-0                          1/1     Running   0             2s
web-1                          1/1     Running   0             2m2s
web-2                          1/1     Running   0             117s
```

`web-0` came back with the **same name** and reattached to its original PVC (`www-web-0`). In a Deployment, the replacement pod would get a new random name and wouldn't have any connection to the deleted pod's storage.

---

## PVC Lifecycle

When you delete a StatefulSet, the PVCs are **not deleted** — they're retained by default. This is a safety measure: stateful data shouldn't disappear just because the workload was removed. To reclaim the storage, you must delete the PVCs manually:

```bash
kubectl delete pvc www-web-0 www-web-1 www-web-2
```

If you recreate the StatefulSet with the same name, the pods will reattach to the existing PVCs — data survives across StatefulSet deletions.
