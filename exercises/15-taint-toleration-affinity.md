# Exercise: Taint, Toleration, and Node Affinity

## Task

You have a 3-node cluster. Node `k8s-worker2` is reserved for GPU workloads.

1. Taint `k8s-worker2` with `gpu=true:NoSchedule`
2. Create a Deployment `gpu-app` in namespace `compute` with 2 replicas using `nginx:alpine` that:
   - Tolerates the `gpu=true:NoSchedule` taint
   - Uses `nodeAffinity` to **require** scheduling only on `k8s-worker2` (match label `kubernetes.io/hostname=k8s-worker2`)
3. Create a second Deployment `regular-app` in namespace `compute` with 2 replicas using `nginx:alpine` that has no tolerations — verify its pods do NOT land on `k8s-worker2`

Write the node name that `gpu-app` pods are running on to `/opt/answers/q13.txt`.

---

## Reference Solution

```bash
# 1. Taint the node
kubectl taint node k8s-worker2 gpu=true:NoSchedule

# 2. gpu-app deployment
kubectl create namespace compute

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-app
  namespace: compute
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gpu-app
  template:
    metadata:
      labels:
        app: gpu-app
    spec:
      tolerations:
        - key: gpu
          value: "true"
          effect: NoSchedule
          operator: Equal
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - k8s-worker2
      containers:
        - name: app
          image: nginx:alpine
EOF

# 3. regular-app (no toleration — should avoid k8s-worker2)
kubectl create deployment regular-app -n compute --image=nginx:alpine --replicas=2

# Verify
kubectl get pods -n compute -o wide

# Write answer
echo "k8s-worker2" > /opt/answers/q13.txt
```

---

## Tips

**Toleration allows, affinity forces.** Toleration alone means the pod *can* land on `k8s-worker2` — scheduler might still put it elsewhere. The `nodeAffinity` with `requiredDuringScheduling` is what forces it there. You need both.

**`operator: Equal` requires a `value`.** If the taint has no value (e.g. `gpu:NoSchedule`), use `operator: Exists` and omit `value`. Check the actual taint with `kubectl describe node k8s-worker2 | grep Taint`.

**`requiredDuringSchedulingIgnoredDuringExecution` = hard requirement.** If no node matches, pods stay Pending. `preferredDuringScheduling...` = soft preference.

**`kubernetes.io/hostname` is auto-labeled on every node.** No need to add a custom label — use this built-in one to target a specific node.

**Cleanup after:** `kubectl taint node k8s-worker2 gpu=true:NoSchedule-` (trailing `-` removes the taint).

---

## Run Notes

