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
