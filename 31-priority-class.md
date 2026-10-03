# PriorityClass

PriorityClass gives pods a relative importance ranking the scheduler uses in two ways:

1. **Scheduling order** — when there's a backlog of pending pods, higher priority ones get scheduled first
2. **Preemption** — if a high-priority pod can't be scheduled because of resource pressure, the scheduler will evict lower-priority pods to make room

---

## Creating PriorityClasses

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "Critical production workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 100
globalDefault: false
description: "Best-effort batch workloads"
```

`value` is just an integer — higher wins. No other units or constraints.

```bash
kubectl get priorityclass
```

```
NAME                      VALUE        GLOBAL-DEFAULT   AGE   PREEMPTIONPOLICY
high-priority             1000000      false            6s    PreemptLowerPriority
low-priority              100          false            6s    PreemptLowerPriority
system-cluster-critical   2000000000   false            44d   PreemptLowerPriority
system-node-critical      2000001000   false            44d   PreemptLowerPriority
```

Note the two built-in system priority classes already present — more on those below.

---

## Assigning a PriorityClass to a Pod

Set `priorityClassName` in the pod spec:

```yaml
spec:
  priorityClassName: low-priority
```

---

## Preemption in Action

Deploy 8 low-priority fillers that consume most of the cluster's resources:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: low-prio-fillers
spec:
  replicas: 8
  selector:
    matchLabels:
      app: low-prio-fillers
  template:
    metadata:
      labels:
        app: low-prio-fillers
    spec:
      priorityClassName: low-priority
      containers:
        - name: filler
          image: nginx:alpine
          resources:
            requests:
              cpu: "500m"
              memory: "256Mi"
```

Then create a high-priority pod with requests that exceed remaining capacity:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: urgent-pod
spec:
  priorityClassName: high-priority
  containers:
    - name: app
      image: nginx:alpine
      resources:
        requests:
          cpu: "1"
          memory: "1Gi"
```

The scheduler evicts low-priority pods to free space:

```
NAME                                READY   STATUS    RESTARTS   AGE
low-prio-fillers-694fbc744c-5tsqp   1/1     Running   0          3m54s
low-prio-fillers-694fbc744c-68hrz   1/1     Running   0          2m56s
low-prio-fillers-694fbc744c-dmmwr   0/1     Pending   0          2s
low-prio-fillers-694fbc744c-lpdzz   0/1     Pending   0          2s
low-prio-fillers-694fbc744c-rjjdb   1/1     Running   0          3m54s
low-prio-fillers-694fbc744c-t5wq7   1/1     Running   0          3m54s
urgent-pod                          1/1     Running   0          2s
```

`urgent-pod` is running; two low-priority pods were evicted and are now `Pending` waiting for resources to free up again.

---

## Built-in System PriorityClasses

```bash
kubectl get priorityclass system-cluster-critical system-node-critical -o yaml
```

Their values are deliberately enormous (2 billion+) to ensure cluster components always outrank anything you'd set manually.

| Class | Value | Scope |
|-------|-------|-------|
| `system-cluster-critical` | 2,000,000,000 | Pods critical for the cluster (e.g. CoreDNS) |
| `system-node-critical` | 2,000,001,000 | Pods critical to this specific node (e.g. kube-apiserver) |
