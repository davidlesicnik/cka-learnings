# Exercise: PersistentVolume, PVC, and Pod

## Task

Create a PersistentVolume `data-pv` of 2Gi with hostPath `/mnt/data`, access mode `ReadWriteOnce`, and storage class `manual`. Create a PVC that binds to it, and a Pod that mounts it at `/usr/share/data`. Write a file from the pod and confirm it exists on the node.

---

## Reference Solution

No imperative commands for PV/PVC — must be YAML. Docs page: **"Configure a Pod to Use a PersistentVolume for Storage"** has all three manifests.

### PersistentVolume

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv
spec:
  storageClassName: manual
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/data"
```

### PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
```

Check it bound:

```bash
kubectl get pvc data-pvc
```

```
NAME       STATUS   VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS
data-pvc   Bound    data-pv   2Gi        RWO            manual
```

`Pending` instead of `Bound` means storageClassName, accessModes, or size don't match the PV — check all three.

### Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: data-pod
spec:
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: data-pvc
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - mountPath: "/usr/share/data"
          name: storage
```

### Write and verify

```bash
kubectl exec data-pod -- sh -c 'echo hello > /usr/share/data/test.txt'
```

Find which node the pod landed on:

```bash
kubectl get pod data-pod -o wide
```

SSH into that node and verify the file is there:

```bash
cat /mnt/data/test.txt
# hello
```

---

## Tips

**PVC must match PV on three fields:** `storageClassName`, `accessModes`, and `storage` request must be <= PV capacity. Any mismatch = PVC stays `Pending` forever.

**hostPath is node-local.** The file only exists on the node where the pod was scheduled. Check `kubectl get pod -o wide` for the node, then look there — not on the control plane.

**PV and PVC are different objects — use different names.** Naming both `data-pv` works but is confusing when debugging. Convention: `data-pv` for the PV, `data-pvc` for the claim.

**The pod references the PVC by `claimName`, never the PV directly.** PV ↔ PVC is a 1:1 binding the cluster manages. The pod only sees the claim.

---

## Run Notes

### Run 1 - 15 minutes

Used docs page "Configure a Pod to Use a PersistentVolume for Storage" — has all three manifests, just modify names and paths. Good page to know.

Forgot hostPath is node-local — looked for the file on the control plane first, found nothing. Checked `kubectl get pod -o wide`, found pod on `k8s-worker1`, found the file there.
