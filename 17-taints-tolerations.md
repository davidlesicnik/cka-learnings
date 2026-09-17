# Taints and Tolerations

Taints live on **nodes** and repel pods. Tolerations live on **pods** and allow them to ignore specific taints.

Think of it as the inverse of node affinity: affinity attracts a pod to a node; a taint pushes pods away from a node unless the pod explicitly tolerates it.

---

## Taint Effects

Three possible effects:

| Effect | New pods | Existing pods |
|--------|----------|---------------|
| `NoSchedule` | Not scheduled on this node | Stay running (unaffected) |
| `PreferNoSchedule` | Soft rule — avoid this node unless nothing else fits | Stay running |
| `NoExecute` | Not scheduled on this node | **Evicted** if they don't have a matching toleration |

`NoExecute` is the strict one — it also evicts already-running pods. You can delay eviction with `tolerationSeconds` on the toleration.

## Taint Format

Taints follow the format `key=value:Effect`. The value is optional — `key:Effect` works too if you don't need a value.

---

## Exercise: NoSchedule Taint

Taint `k8s-worker1` so nothing schedules there without a toleration:

```bash
kubectl taint nodes k8s-worker1 dedicated=special:NoSchedule
```

```
node/k8s-worker1 tainted
```

```bash
kubectl describe node k8s-worker1 | grep -i taint
```

```
Taints:             dedicated=special:NoSchedule
```

To isolate the taint test, cordon `k8s-worker2` so it accepts no new pods — this way `k8s-worker1` is the only option and the taint effect is clearly visible:

```bash
kubectl cordon k8s-worker2
```

Now `k8s-worker1` is the only available worker — but it has a taint. Deploy a pod without a toleration:

```bash
kubectl run notol-pod --image=nginx:alpine
kubectl get pods notol-pod -o wide
```

```
NAME        READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE   READINESS GATES
notol-pod   0/1     Pending   0          10s   <none>   <none>   <none>           <none>
```

Stuck `Pending` — no eligible node.

---

## Exercise: Pod with Toleration

Create `tol-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tol-pod
spec:
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "special"
      effect: "NoSchedule"
  containers:
    - name: nginx
      image: nginx:alpine
```

The toleration matches the taint exactly: same key, value, and effect. Operator `Equal` means key+value must match. You can also use `Exists` (omit `value`) to tolerate any taint with that key regardless of value.

```bash
kubectl apply -f tol-pod.yaml
kubectl get pod tol-pod -o wide
```

```
NAME      READY   STATUS    RESTARTS   AGE   IP               NODE          NOMINATED NODE   READINESS GATES
tol-pod   1/1     Running   0          7s    10.244.194.107   k8s-worker1   <none>           <none>
```

Deployed to `k8s-worker1` because the toleration bypassed the taint.

> **Important:** a toleration allows a pod to schedule on a tainted node — it does not force it there. If other untainted nodes are available, the scheduler can still place the pod elsewhere. To guarantee placement on a specific node, combine a toleration with a node affinity.

---

## Removing a Taint

Append `-` to the full taint string to remove it:

```bash
kubectl taint nodes k8s-worker1 dedicated=special:NoSchedule-
```

```
node/k8s-worker1 untainted
```

The `-` suffix is the removal syntax — it's the same pattern used elsewhere in kubectl (e.g. removing labels). You must specify the full taint (`key=value:Effect-`) so Kubernetes knows exactly which taint to remove.

---

## Cleanup

```bash
kubectl delete pod notol-pod tol-pod
kubectl uncordon k8s-worker2
```

---

## Control Plane Taint

The control plane node has a built-in `NoSchedule` taint (`node-role.kubernetes.io/control-plane:NoSchedule`) which is why regular pods don't land there. DaemonSets like Calico add a matching toleration to run on every node including the control plane — as covered in [DaemonSets](13-daemon-set.md).
