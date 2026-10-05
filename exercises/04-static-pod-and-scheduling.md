# Exercise: Static Pod and Forced Node Scheduling

## Task

On `k8s-cp1`, create a static pod named `static-web` using image `nginx:1.31.4` in the default namespace. Then create a separate regular pod that must be scheduled on the control plane node, using the correct toleration and nodeSelector. Show both pods running and which node each is on.

---

## Reference Solution

### Verify (final check)

```bash
kubectl get pods -o wide
```

Both pods should show `NODE: k8s-cp1`:

```
NAME                 READY   STATUS    NODE
separate-pod         1/1     Running   k8s-cp1
static-web-k8s-cp1   1/1     Running   k8s-cp1
```

---

### Part 1: Static Pod

Generate the manifest with dry-run, pipe directly to the manifests directory:

```bash
kubectl run static-web --image=nginx:1.31.4 --dry-run=client -o yaml > /etc/kubernetes/manifests/static-web.yaml
```

No edits needed — kubelet accepts the dry-run output as-is. Wait up to 60 seconds:

```bash
kubectl get pod static-web-k8s-cp1
```

The `-k8s-cp1` suffix is automatic — kubelet appends the node hostname. This is the tell that a pod is static.

> **`kubectl run pod static-web` is wrong.** `pod` becomes the pod name and `static-web` becomes a container arg — generates a broken manifest. The command is `kubectl run static-web` (no `pod`).

### Part 2: Pod Forced to the Control Plane

First, find the control plane taint:

```bash
kubectl describe node k8s-cp1 | grep Taint
```

```
Taints: node-role.kubernetes.io/control-plane:NoSchedule
```

Use that taint key for both the toleration and the nodeSelector:

```bash
kubectl run cp-pod --image=nginx:1.31.4 --dry-run=client -o yaml > cp-pod.yaml
```

Edit `cp-pod.yaml` — add under `spec:`:

```yaml
spec:
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    effect: NoSchedule
    operator: Exists
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  containers:
  ...
```

```bash
kubectl apply -f cp-pod.yaml
```

### Verify both

```bash
kubectl get pods -o wide
```

Expected output:
```
NAME                  READY   STATUS    NODE
cp-pod                1/1     Running   k8s-cp1
static-web-k8s-cp1   1/1     Running   k8s-cp1
```

---

## Tips

**Toleration allows, nodeSelector forces.** A toleration alone means the pod *can* land on the control plane — the scheduler can still place it on a worker if resources are available. The nodeSelector (or nodeAffinity) is what *forces* it there. You need both.

**Find the taint before writing the toleration.** Don't memorize `node-role.kubernetes.io/control-plane` — just `kubectl describe node <cp-node> | grep Taint` on the exam. The taint key is the same key you use for `nodeSelector`.

**`operator: Exists` vs `operator: Equal`.** Use `Exists` when you only need to match the key and effect, without caring about the value. Use `Equal` when you need to match a specific value. For the control plane taint (no value), `Exists` is correct.

**Static pod directory path if unsure:**
```bash
grep staticPodPath /var/lib/kubelet/config.yaml
```

---

## Run Notes

### Run 1 - 20 minutes

Static pod: used `kubectl run pod static-web` (wrong — `pod` is the name, `static-web` becomes an arg). Had to manually remove the extra args from the generated YAML. 

Second pod: couldn't remember the control plane taint key. Used `kubectl describe node k8s-cp1` to find it — correct approach, use this every time rather than guessing. Found the taint, used same label for nodeSelector.

### Run 2 — 5 minutes

Static pod: used `kubectl run --help` for syntax — ~1.5 minutes. Gotcha: copied the image and name from the example command instead of the exercise spec. Always substitute before running.

Second pod: `--dry-run=client -o yaml` to generate the base, then added toleration and nodeSelector manually.
- Toleration: "Taints and Tolerations" docs page has an example near the top — used `operator: Exists`
- nodeSelector: "Assign Pods to Nodes" docs page has an example — same `Exists` operator pattern

20 min → 5 min.
