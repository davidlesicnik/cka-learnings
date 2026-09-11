# Storage: Persistent Volumes and Claims

Persistent Volumes (PVs) are pieces of storage that exist independently of any pod. Unlike a container's filesystem (which is lost when the container restarts), PV data persists. Pods access PVs through **PersistentVolumeClaims (PVCs)** — a request for storage that Kubernetes matches to an available PV.

The relationship:

```
PV (the actual storage) ←— PVC (a claim/request) ←— Pod (mounts the claim)
```

This separation lets cluster admins provision storage (PVs) and developers request it (PVCs) without needing to know the underlying storage details.

---

## Persistent Volumes (PV)

Since we're on a local cluster, we'll use the `hostPath` type — it maps a directory on the node's filesystem into the cluster as a PV.

> **hostPath is not production-safe.** It ties the PV to a specific node. If the pod gets rescheduled to a different node, it won't find the data. In production you'd use networked storage (NFS, Ceph, EBS, etc.). For learning, hostPath is fine.

### Setup the host directory

On the node where the pod will run:

```bash
mkdir /mnt/data
sudo chmod 777 /mnt/data
```

(`chmod 777` is quick-and-dirty — the focus here is PVs, not Linux permissions.)

### Create the PV

Create `pv-hostpath.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-hostpath
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/data
```

**Exam-relevant fields:**

| Field | Value | Meaning |
|-------|-------|---------|
| `accessModes` | `ReadWriteOnce` | One node can mount it read-write at a time. Other options: `ReadOnlyMany` (many nodes, read-only), `ReadWriteMany` (many nodes, read-write) |
| `persistentVolumeReclaimPolicy` | `Retain` | When the PVC is deleted, the PV and its data stay. `Delete` auto-removes the PV and underlying storage. `Recycle` is deprecated |
| `storageClassName` | `manual` | An arbitrary label — not a real StorageClass object. Just needs to match on the PVC side so Kubernetes binds the right PV to the right claim |

Apply and verify:

```bash
kubectl apply -f pv-hostpath.yaml
kubectl get pv
```

```
NAME          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pv-hostpath   1Gi        RWO            Retain           Available           manual         <unset>                          88s
```

`STATUS: Available` means no PVC has claimed this PV yet. `RWO` is shorthand for `ReadWriteOnce`.

---

## PersistentVolumeClaims (PVC)

A PVC is a request for storage. Kubernetes matches it to an available PV based on:
- `storageClassName` must match
- `accessModes` must match
- Requested `storage` must be <= PV's capacity

Create `pvc-hostpath.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-hostpath
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: 1Gi
```

The `storageClassName: manual` matches our PV, and `accessModes` lines up too.

Apply and verify:

```bash
kubectl apply -f pvc-hostpath.yaml
kubectl get pvc
```

```
NAME           STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
pvc-hostpath   Bound    pv-hostpath   1Gi        RWO            manual         <unset>                 33s
```

`STATUS: Bound` — Kubernetes matched this PVC to `pv-hostpath`. If no matching PV existed, it would stay `Pending`.

The PV status also changes:

```
STATUS: Available → Bound
CLAIM: default/pvc-hostpath
```

This is a 1:1 binding — once bound, no other PVC can use this PV.

---

## Mounting a PVC in a Pod

Create `pod-with-pvc.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-pvc
spec:
  containers:
    - name: app
      image: nginx:alpine
      volumeMounts:
        - name: storage
          mountPath: /usr/share/nginx/html
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: pvc-hostpath
```

**How it connects:** `volumes[].name` links to `volumeMounts[].name` — the `name: storage` string ties them together. The pod references the PVC by name (`claimName`), never the PV directly. This is the abstraction: pods only know about claims, not the underlying storage.

```bash
kubectl apply -f pod-with-pvc.yaml
```

### Testing

Check which node the pod landed on:

```bash
kubectl get pod pod-with-pvc -o wide
```

```
NAME           READY   STATUS    RESTARTS   AGE   IP              NODE          NOMINATED NODE   READINESS GATES
pod-with-pvc   1/1     Running   0          10s   10.244.126.15   k8s-worker2   <none>           <none>
```

The pod is on `k8s-worker2`. Since hostPath is node-local, we write to the directory on **that specific node**:

```bash
multipass shell k8s-worker2
echo "hello from hostPath" | sudo tee /mnt/data/index.html
```

Verify the file is visible inside the pod:

```bash
kubectl exec pod-with-pvc -- cat /usr/share/nginx/html/index.html
```

```
hello from hostPath
```

The hostPath directory on the node and `/usr/share/nginx/html` inside the pod are the same filesystem location. Changes on either side are immediately visible to the other.

> **hostPath gotcha demonstrated:** We had to check which node the pod was on and write the file there. If this pod gets rescheduled to `k8s-worker1`, it would find an empty `/mnt/data` (or the directory might not even exist). This is why hostPath doesn't work for production — data doesn't follow the pod.
