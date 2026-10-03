# LimitRange

LimitRange is a namespace-scoped policy that does two separate jobs:

**Job 1 — auto-fill missing resource fields.** If someone creates a pod without specifying requests or limits, the LimitRange injects defaults automatically. This can surprise people who don't know the LimitRange exists (their pod suddenly has resources they didn't write), but it's a useful safety net: pods with no requests are dangerous at scale because the scheduler has no CPU or memory signal for bin-packing.

**Job 2 — enforce min/max bounds.** Even if someone does define their own requests/limits, LimitRange can reject the pod outright if those numbers fall outside the allowed range. This happens at admission time — the pod never gets created.

---

## Setup

```bash
kubectl create namespace limitrange-demo
```

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: limitrange-demo
spec:
  limits:
    - type: Container
      default:
        cpu: "200m"
        memory: "256Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "1"
        memory: "512Mi"
      min:
        cpu: "50m"
        memory: "64Mi"
```

Four fields:

| Field | Job | Meaning |
|-------|-----|---------|
| `default` | 1 | Limits injected when none specified |
| `defaultRequest` | 1 | Requests injected when none specified |
| `max` | 2 | Hard ceiling — pod rejected if it exceeds this |
| `min` | 2 | Hard floor — pod rejected if it goes below this |

```bash
kubectl -n limitrange-demo describe limitrange default-limits
```

```
Type        Resource  Min   Max    Default Request  Default Limit  Max Limit/Request Ratio
----        --------  ---   ---    ---------------  -------------  -----------------------
Container   memory    64Mi  512Mi  128Mi            256Mi          -
Container   cpu       50m   1      100m             200m           -
```

---

## Job 1: Default Injection

Create a pod with no resource fields:

```bash
kubectl run bare-pod --image=nginx:alpine -n limitrange-demo
```

Describe it:

```
Limits:
  cpu:     200m
  memory:  256Mi
Requests:
  cpu:     100m
  memory:  128Mi
```

Resources were injected by the LimitRange — the pod manifest never specified them.

---

## Job 2: Bounds Enforcement

Try to apply a pod that exceeds the CPU max:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: oversized-pod
  namespace: limitrange-demo
spec:
  containers:
    - name: app
      image: nginx:alpine
      resources:
        requests:
          cpu: "2"
        limits:
          cpu: "2"
```

```bash
kubectl apply -f oversized-pod.yaml
```

```
Error from server (Forbidden): error when creating "oversized-pod.yaml": pods "oversized-pod" is forbidden: maximum cpu usage per Container is 1, but limit is 2
```

Rejected immediately at the API server — the pod never reaches the scheduler.
