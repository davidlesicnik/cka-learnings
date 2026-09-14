# Storage Classes and Dynamic Provisioning

In the previous storage doc, we manually created a PV then claimed it with a PVC. This is **static provisioning** — an admin must pre-create every PV.

**Storage Classes** enable **dynamic provisioning** — the PVC references a StorageClass, and a provisioner automatically creates the PV on demand. No admin intervention needed per volume.

This is how most production clusters work. Cloud providers ship default StorageClasses (e.g. `gp2` on AWS, `standard` on GKE) that provision cloud disks automatically.

---

## Static vs Dynamic Provisioning

| | Static | Dynamic |
|---|--------|---------|
| PV creation | Admin creates PVs manually | Provisioner creates PVs automatically |
| PVC references | `storageClassName` matching a PV's label | `storageClassName` matching a StorageClass object |
| Scaling | Doesn't scale — every volume needs admin work | Self-service — developers create PVCs, storage appears |
| Use case | Learning, specific storage requirements | Production, general-purpose storage |

---

## Setting Up a Provisioner

A StorageClass needs a **provisioner** — the controller that actually creates the storage when a PVC is made. Similar to how a LoadBalancer Service needs a load balancer controller.

For our bare-metal cluster, we'll use **Rancher's local-path-provisioner** — it creates hostPath-based PVs automatically on the node where the pod is scheduled.

### Install

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
```

### Verify

Check the provisioner pod and the StorageClass it created:

```bash
kubectl get pods -n local-path-storage
kubectl get storageclass
```

```
NAME                                      READY   STATUS    RESTARTS   AGE
local-path-provisioner-5f584dbd7d-vx4kn   1/1     Running   0          9s

NAME         PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  9s
```

**StorageClass fields explained:**

| Field | Value | Meaning |
|-------|-------|---------|
| `PROVISIONER` | `rancher.io/local-path` | Which controller creates the PVs |
| `RECLAIMPOLICY` | `Delete` | PV and data are auto-deleted when PVC is removed (unlike `Retain` from our manual PV) |
| `VOLUMEBINDINGMODE` | `WaitForFirstConsumer` | Don't create the PV until a pod actually uses the PVC. This lets the scheduler pick the node first, then create storage on that node |
| `ALLOWVOLUMEEXPANSION` | `false` | Can't resize volumes after creation |

`WaitForFirstConsumer` is important for node-local storage — if the PV were created immediately, it might land on a different node than where the pod gets scheduled.

---

## Using Dynamic Provisioning

Create `pvc-dynamic.yaml` — notice there's no PV manifest at all:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-dynamic
spec:
  storageClassName: local-path
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

The key difference from static provisioning: `storageClassName: local-path` points to a real StorageClass object (not just an arbitrary label like `manual`). The provisioner watches for PVCs referencing its StorageClass and creates PVs to satisfy them.

```bash
kubectl apply -f pvc-dynamic.yaml
kubectl get pvc pvc-dynamic
```

```
NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
pvc-dynamic   Pending                                      local-path     <unset>                 12s
```

`STATUS: Pending` is expected here — because the binding mode is `WaitForFirstConsumer`, the PV won't be created until a pod mounts this PVC. Once a pod references `pvc-dynamic`, the provisioner will:

1. See which node the pod is scheduled on
2. Create a hostPath directory on that node
3. Create a PV pointing to that directory
4. Bind the PVC to the new PV
5. PVC status changes to `Bound`
