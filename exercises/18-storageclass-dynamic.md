# Exercise: StorageClass and Dynamic Provisioning

## Task

1. Create a `StorageClass` named `fast-local` using the `rancher.io/local-path` provisioner with:
   - `reclaimPolicy: Delete`
   - `volumeBindingMode: WaitForFirstConsumer`

2. Create a `PersistentVolumeClaim` named `data-pvc` in namespace `storage-demo` that:
   - Requests `500Mi` of storage
   - Uses `storageClassName: fast-local`
   - Access mode: `ReadWriteOnce`

3. Create a Pod named `writer` in `storage-demo` that:
   - Mounts `data-pvc` at `/data`
   - Runs: `sh -c "echo 'hello from pod' > /data/test.txt && sleep 3600"`

4. Verify the file exists in the volume.

5. Write the name of the StorageClass used by `data-pvc` to `/opt/answers/q16.txt`.

---

## Reference Solution

```bash
# 1. StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF

# 2. Namespace + PVC
kubectl create namespace storage-demo

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: storage-demo
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: fast-local
  resources:
    requests:
      storage: 500Mi
EOF

# PVC stays Pending until pod binds it (WaitForFirstConsumer)
kubectl get pvc -n storage-demo

# 3. Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: storage-demo
spec:
  containers:
    - name: writer
      image: busybox
      command: ["sh", "-c", "echo 'hello from pod' > /data/test.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data-pvc
EOF

# 4. Verify
kubectl exec writer -n storage-demo -- cat /data/test.txt

# 5. Write answer
kubectl get pvc data-pvc -n storage-demo -o jsonpath='{.spec.storageClassName}' > /opt/answers/q16.txt
```

---

## Tips

**`WaitForFirstConsumer` = PVC stays `Pending` until a pod requests it.** This is normal — not a bug. Once the pod is created, the PVC binds and becomes `Bound`.

**`Immediate` binding mode** = PVC binds as soon as created. Use `WaitForFirstConsumer` for local storage (node-affinity matters for placement).

**Dynamic vs static:** With a StorageClass, no manual PV creation needed — the provisioner creates one automatically. The PVC binds to the auto-created PV.

**`reclaimPolicy: Delete`** = PV and underlying storage deleted when PVC is deleted. `Retain` = PV stays, requires manual cleanup.

**Exam will likely give you the provisioner name** — you won't need to know `rancher.io/local-path` from memory. They'll either tell you or point you to an existing StorageClass.

**`kubectl get sc`** — list available StorageClasses. The one marked `(default)` is used when no `storageClassName` is specified.

---

## Run Notes

### Run 1 — 7m45s

No `kubectl create storageclass` command exists — must write YAML. Most time spent finding a StorageClass template. Docs page "Configure a Pod to Use a PersistentVolume for Storage" covered PVC and Pod setup. StorageClass YAML is short — worth memorizing the four fields (`apiVersion`, `provisioner`, `reclaimPolicy`, `volumeBindingMode`).
