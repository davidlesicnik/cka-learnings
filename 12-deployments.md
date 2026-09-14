# Deployments

A Deployment manages pods through an intermediary: the **ReplicaSet**. The hierarchy is:

```
Deployment → ReplicaSet → Pods
```

The Deployment never touches pods directly — it only manages ReplicaSets. When an update is deployed, it creates a new ReplicaSet and scales it up while scaling the old one down. By default, Kubernetes keeps the last **10 ReplicaSets** in history, enabling quick rollbacks.

---

## Creating a Deployment

Create `rollout-demo.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rollout-demo
  labels:
    app: rollout-demo
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: rollout-demo
  template:
    metadata:
      labels:
        app: rollout-demo
    spec:
      containers:
        - name: nginx
          image: nginx:1.25-alpine
```

**Key fields:**

| Field | Meaning |
|-------|---------|
| `replicas` | Desired number of pods |
| `strategy.type` | `RollingUpdate` (default) or `Recreate` (kills all old pods before creating new ones) |
| `maxSurge` | How many extra pods above `replicas` are allowed during an update. Here: up to 5 pods can exist temporarily (4 + 1) |
| `maxUnavailable` | How many pods can be down during an update. Here: at most 1 pod can be unavailable, so minimum 3 always running |
| `selector.matchLabels` | Must match `template.metadata.labels` — this is how the Deployment finds its pods |

`maxSurge` and `maxUnavailable` together control the rollout pace. Setting both to 1 means: create 1 new pod, wait for it to be ready, then terminate 1 old pod. Repeat until done.

```bash
kubectl apply -f rollout-demo.yaml
```

### Verify

```bash
kubectl get deploy
```

```
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
rollout-demo   4/4     4            4           4s
```

Check the ReplicaSet the Deployment created:

```bash
kubectl get replicaset
```

```
NAME                     DESIRED   CURRENT   READY   AGE
rollout-demo-d79786d47   4         4         4       19s
```

The hash suffix (`d79786d47`) is generated from the pod template spec. A different image or config = different hash = different ReplicaSet.

---

## Rolling Updates

Trigger a rolling update by changing the container image:

```bash
kubectl set image deployment/rollout-demo nginx=nginx:1.27-alpine
```

During the rollout, the Deployment creates a new ReplicaSet and gradually shifts pods over. Once complete:

```bash
kubectl get replicaset
```

```
NAME                      DESIRED   CURRENT   READY   AGE
rollout-demo-6b9fbcdf85   4         4         4       12s
rollout-demo-d79786d47    0         0         0       96s
```

The old ReplicaSet is scaled to 0 but **not deleted** — it stays around for rollback purposes.

### Rollout history

```bash
kubectl rollout history deployment/rollout-demo
```

```
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

`CHANGE-CAUSE` is `<none>` because we didn't annotate the Deployment. You can add a cause with:

```bash
kubectl annotate deployment/rollout-demo kubernetes.io/change-cause="Updated nginx to 1.27"
```

---

## Rollbacks

### Undo to previous revision

```bash
kubectl rollout undo deployment/rollout-demo
```

```
Warning: resource deployments/rollout-demo was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/rollout-demo rolled back
```

**This warning is worth understanding.** When you use `kubectl apply`, Kubernetes stores the manifest in an annotation (`last-applied-configuration`). A rollback via `rollout undo` changes the live object but doesn't update that annotation — so the next `kubectl apply` from your original manifest would overwrite the rollback. The warning recommends editing your manifest file and re-applying instead. In practice: use `rollout undo` for emergencies, update the manifest for planned changes.

Verify the old ReplicaSet is back:

```bash
kubectl get rs
```

```
NAME                     DESIRED   CURRENT   READY   AGE
rollout-demo-d79786d47   4         4         4       5m
```

### Undo to a specific revision

```bash
kubectl rollout undo deployment/rollout-demo --to-revision=1
```

Useful when you've had multiple updates and need to go back further than just the previous one. The revision number comes from `rollout history`.

---

## Scaling

Three ways to scale a Deployment:

### 1. Imperative: `kubectl scale`

```bash
kubectl scale deployment rollout-demo --replicas=6
kubectl get deployment
```

```
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
rollout-demo   6/6     6            6           6m56s
```

Scale back down:

```bash
kubectl scale deployment rollout-demo --replicas=4
```

```
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
rollout-demo   4/4     4            4           7m38s
```

Pods are terminated gracefully when scaling down — they receive a `SIGTERM` and get a grace period (default 30s) before being killed.

### 2. Declarative: edit the manifest and re-apply

Change `replicas` in your YAML file:

```yaml
spec:
  replicas: 6
```

Then:

```bash
kubectl apply -f rollout-demo.yaml
```

```
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
rollout-demo   6/6     6            6           9m13s
```

This is the preferred approach — your manifest stays in sync with the cluster state, and the change is tracked in version control.

### 3. Live edit: `kubectl edit`

```bash
kubectl edit deployment rollout-demo
```

Opens the live object in your editor. Changes apply immediately on save. This is quick for experimentation but has the same drift problem as `rollout undo` — your local manifest won't reflect the change.

### Imperative vs Declarative

| Approach | Pros | Cons |
|----------|------|------|
| `kubectl scale` | Fast, one command | Manifest drift — cluster and YAML disagree |
| Edit YAML + `apply` | Manifest stays in sync, trackable in git | Slower (edit file, apply) |
| `kubectl edit` | Quick for experiments | Same drift as imperative, no git history |

For the CKA exam, know all three. For real work, declarative is the standard.
