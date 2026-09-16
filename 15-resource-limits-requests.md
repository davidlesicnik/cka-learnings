# Resource Requests and Limits

Requests and limits control two different things — mixing them up is a common mistake.

| | Requests | Limits |
|---|---------|--------|
| **What it does** | Minimum guaranteed resources. The scheduler uses these to decide which node has room for the pod | Hard ceiling the pod cannot exceed |
| **CPU exceeded** | N/A (requests are a guarantee, not a cap) | CPU gets **throttled** (slowed down, not killed) |
| **Memory exceeded** | N/A | Pod gets **OOM killed** (terminated immediately) |
| **If not set** | Scheduler has no resource info, pod can land anywhere | No ceiling, pod can consume unlimited resources |

The key difference: exceeding CPU limits slows your service down. Exceeding memory limits **kills your app**. This is because CPU is compressible (you can throttle it), but memory is not (you can't take memory back from a process without killing it).

---

## CPU Units

CPU is measured in **millicores** (m):

| Value | Meaning |
|-------|---------|
| `1000m` | 1 full CPU core |
| `500m` | Half a core |
| `100m` | 0.1 core (10% of one core) |
| `1` | Same as `1000m` |

---

## QoS Classes

Requests and limits together determine a pod's **Quality of Service class**, which affects eviction priority when a node runs out of resources:

| QoS Class | Condition | Eviction priority |
|-----------|-----------|-------------------|
| **Guaranteed** | `requests == limits` for all containers | Evicted **last** (highest priority) |
| **Burstable** | Requests and limits set but differ | Evicted second |
| **BestEffort** | Neither requests nor limits set | Evicted **first** (lowest priority) |

When a node is under memory pressure, Kubernetes kills BestEffort pods first, then Burstable, then Guaranteed. For critical workloads, set requests equal to limits.

---

## Example: Burstable Pod

Create `resource-demo.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resource-demo
spec:
  containers:
    - name: app
      image: nginx:alpine
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 128Mi
```

Requests: 0.1 core CPU, 64Mi memory. Limits: 0.2 core CPU, 128Mi memory.

This means the scheduler guarantees a node with at least 100m CPU and 64Mi free, but the pod can burst up to 200m / 128Mi.

```bash
kubectl apply -f resource-demo.yaml
kubectl describe pod resource-demo
```

```
Limits:
      cpu:     200m
      memory:  128Mi
    Requests:
      cpu:        100m
      memory:     64Mi
```

```
QoS Class:                   Burstable
```

Burstable because limits != requests.

---

## Example: OOM Kill

Deliberately create a pod that exceeds its memory limit — 20Mi limit, but we give it a task that allocates ~100MB:

Create `oom-demo.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: oom-demo
spec:
  containers:
    - name: hog
      image: busybox
      resources:
        requests:
          memory: 10Mi
        limits:
          memory: 20Mi
      command: ["sh", "-c", "cat /dev/zero | head -c 100m | tail"]
```

```bash
kubectl apply -f oom-demo.yaml
kubectl get pods
```

```
oom-demo                   0/1     OOMKilled   1 (2s ago)    3s
```

Describe shows the termination details:

```bash
kubectl describe pod oom-demo
```

```
State:          Terminated
      Reason:       OOMKilled
      Exit Code:    137
```

**Exit code 137** = the container was killed by a signal. Specifically: 128 + 9 (SIGKILL) = 137. This is the kernel's OOM killer in action — when a container tries to allocate memory beyond its cgroup limit, the kernel sends SIGKILL. The pod will enter CrashLoopBackOff as Kubernetes keeps restarting it and it keeps getting killed.

Useful to remember: even when the `Reason` field doesn't explicitly say OOMKilled, **exit code 137 always means the process was SIGKILL'd** — and in a Kubernetes context, that's almost always an OOM kill.
