# Troubleshooting Drills — Part 2

---

## Drill 6: Pod Stuck in CrashLoopBackOff (Multiple Causes)

CrashLoopBackOff means the container starts, crashes, and Kubernetes keeps restarting it with exponential backoff. The cause can be almost anything — the exit code is the first filter.

### Setup

Create `crash-demo.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crash-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crash-demo
  template:
    metadata:
      labels:
        app: crash-demo
    spec:
      containers:
        - name: app
          image: busybox
          command:
            - sh
            - -c
            - |
              if [ -z "$DB_HOST" ]; then
                echo "FATAL: DB_HOST is not set" >&2
                exit 1
              fi
              echo "connected to $DB_HOST"
              sleep 3600
```

```bash
kubectl apply -f crash-demo.yaml
```

### Symptoms

```bash
kubectl get pods
```

```
NAME                          READY   STATUS             RESTARTS     AGE
crash-demo-844bfcd77d-zq485   0/1     CrashLoopBackOff   1 (7s ago)   10s
```

### Diagnosis

Describe the pod and check `Last State`:

```bash
kubectl describe pod crash-demo-844bfcd77d-zq485
```

```
Last State:     Terminated
  Reason:       Error
  Exit Code:    1
```

**Exit code is the first decision point:**

| Exit code | Meaning | Next step |
|-----------|---------|-----------|
| `1` (or small number) | App exited with an error | Read the logs |
| `137` | SIGKILL — usually OOMKilled | Check `Reason: OOMKilled`, review memory limits |
| `127` | Command not found | Bad `command:` or wrong image |
| `126` | Command not executable | Permission issue on the binary |
| `139` | Segfault | Application crash, read logs |

Exit code `1` — read the logs:

```bash
kubectl logs crash-demo-844bfcd77d-zq485
```

```
FATAL: DB_HOST is not set
```

If the pod cycles too fast and current logs are empty, use `--previous` to read the last terminated container's logs:

```bash
kubectl logs crash-demo-844bfcd77d-zq485 --previous
```

Missing `DB_HOST` env var is the cause.

### Fix

Add the env var to the manifest:

```yaml
spec:
  containers:
    - name: app
      env:
        - name: DB_HOST
          value: db.example.com
```

```bash
kubectl apply -f crash-demo.yaml
kubectl get pods
```

```
NAME                         READY   STATUS    RESTARTS   AGE
crash-demo-ff8f484b6-mm2x5   1/1     Running   0          12s
```

### Key takeaway

CrashLoopBackOff diagnostic order: `kubectl get pods` → `kubectl describe pod` (exit code) → act on the exit code → `kubectl logs` (or `--previous`). The exit code tells you which direction to look before you even open the logs.

## Drill 7: Pod Stuck in Pending

`Pending` means the scheduler can't find a node to place the pod on. Common causes: insufficient resources, unsatisfied node affinity, untolerated taint, or no PV available. Here we trigger it with requests that exceed node capacity.

### Setup

Create `pending-demo.yaml` with requests that no node can satisfy (64Gi RAM):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pending-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pending-demo
  template:
    metadata:
      labels:
        app: pending-demo
    spec:
      containers:
        - name: app
          image: nginx:alpine
          resources:
            requests:
              cpu: "2"
              memory: 64Gi
```

```bash
kubectl apply -f pending-demo.yaml
```

### Symptoms

```bash
kubectl get deployment pending-demo
```

```
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
pending-demo   0/1     1            0           103s
```

```bash
kubectl get pods
```

```
NAME                            READY   STATUS    RESTARTS   AGE
pending-demo-5d8f6f85d5-lftkt   0/1     Pending   0          117s
```

### Diagnosis

```bash
kubectl describe pod pending-demo-5d8f6f85d5-lftkt
```

```
Events:
  Warning  FailedScheduling  36s (x4 over 2m39s)  default-scheduler  0/3 nodes are available: 1 Insufficient cpu, 1 node(s) had untolerated taint(s), 2 Insufficient memory.
```

The scheduler tells you exactly why each node was rejected:
- `1 node(s) had untolerated taint(s)` — the control plane node, expected
- `2 Insufficient memory` — both worker nodes don't have 64Gi free

Confirm actual allocatable resources on a worker:

```bash
kubectl describe node k8s-worker1 | grep -A 8 Allocatable
```

```
Allocatable:
  cpu:                2
  memory:             1911032Ki
  pods:               110
```

`1911032Ki` ≈ 1.8Gi. Pod requests 64Gi — no match.

### Fix

Reduce the requests to fit within what the nodes actually have:

```yaml
resources:
  requests:
    cpu: "500m"
    memory: 128Mi
```

### Key takeaway

`Pending` diagnostic path: `kubectl describe pod` → read the `FailedScheduling` event — the scheduler lists every node and why it was rejected. This one message tells you whether it's a resource problem, a taint problem, an affinity problem, or something else entirely.

Other common `Pending` causes seen in `FailedScheduling` events:

| Event message | Cause | Fix |
|---------------|-------|-----|
| No events at all | Scheduler isn't running | `kubectl -n kube-system get pods \| grep scheduler` — see drill 4 |
| `unbound immediate PersistentVolumeClaims` | PVC not bound | Fix the PV or StorageClass |
| `didn't match Pod's node affinity/selector` | No node satisfies the affinity rule | Check nodeSelector / affinity constraints vs node labels |
