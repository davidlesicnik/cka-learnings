# Exercise: Pod Failure Triage

## Task

Namespace `debug` has 4 broken pods. Diagnose each without deleting or recreating them.

1. `crash-pod` — identify why it's crash-looping, write the exit code to `/opt/answers/q14a.txt`
2. `pull-pod` — identify the image pull failure reason, write the image name to `/opt/answers/q14b.txt`
3. `oom-pod` — identify why it keeps restarting, write the reason to `/opt/answers/q14c.txt`
4. `pending-pod` — identify why it's stuck Pending, write the reason to `/opt/answers/q14d.txt`

Do not fix the pods — diagnosis only.

## Setup

```bash
kubectl create namespace debug

# 1. CrashLoopBackOff — exits immediately with error
kubectl run crash-pod -n debug --image=busybox -- sh -c "echo starting && exit 1"

# 2. ImagePullBackOff — nonexistent image tag
kubectl run pull-pod -n debug --image=nginx:v99.99.99

# 3. OOMKilled — memory limit too low
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: oom-pod
  namespace: debug
spec:
  containers:
  - name: oom-pod
    image: busybox
    command: ["sh", "-c", "dd if=/dev/zero of=/dev/shm/bigfile bs=1M count=50"]
    resources:
      limits:
        memory: 10Mi
EOF

# 4. Pending — resource request impossible to satisfy
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pending-pod
  namespace: debug
spec:
  containers:
  - name: pending-pod
    image: nginx
    resources:
      requests:
        cpu: "99"
EOF
```

---

## Reference Solution

```bash
# Overview
kubectl get pods -n debug

# 1. crash-pod
kubectl describe pod crash-pod -n debug | grep -A5 "Last State"
kubectl logs crash-pod -n debug --previous
# Exit code 1
echo "1" > /opt/answers/q14a.txt

# 2. pull-pod
kubectl describe pod pull-pod -n debug | grep -A3 "Failed"
# Image: nginx:v99.99.99
echo "nginx:v99.99.99" > /opt/answers/q14b.txt

# 3. oom-pod
kubectl describe pod oom-pod -n debug | grep -A5 "Last State"
# OOMKilled, exit code 137
echo "OOMKilled" > /opt/answers/q14c.txt

# 4. pending-pod
kubectl describe pod pending-pod -n debug | grep -A10 "Events"
# Insufficient cpu
echo "Insufficient cpu" > /opt/answers/q14d.txt
```

---

## Tips

**Triage order:** `kubectl get pods -n <ns>` → spot STATUS → `kubectl describe pod <name>` → check Events and Last State.

**CrashLoopBackOff:** `kubectl logs <pod> --previous` shows the last crash's output. Exit code is in `describe` under `Last State: Terminated → Exit Code`.

**ImagePullBackOff vs ErrImagePull:** ErrImagePull is the first failure. ImagePullBackOff is after retries begin. Both mean the image doesn't exist or can't be pulled — check registry, name, tag.

**OOMKilled = exit code 137.** The kernel killed the process. `describe` shows `OOMKilled: true` under Last State. Fix: increase `limits.memory` or reduce the workload.

**Pending pod:** Always check `Events` section in `describe`. "0/N nodes are available: N Insufficient cpu" = requests too high. Also watch for: missing PVC, no matching node selector, taint with no toleration.

**`--previous` flag:** Without it, `logs` shows the current (possibly empty) run. With it, shows the prior crashed container's output.

---

## Run Notes

### Run 1 — 3m30s

- `crash-pod`: exit code 1 from `kubectl describe`
- `oom-pod`: kubelet event showed OOM-killed — memory limit too low
- `pull-pod`: image `nginx:v99.99.99` doesn't exist — visible in Events
- `pending-pod`: took a moment — suspected CPU from Events, confirmed via `kubectl edit` → `requests.cpu: "99"`
