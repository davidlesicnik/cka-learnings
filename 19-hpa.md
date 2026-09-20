# Horizontal Pod Autoscaler (HPA)

HPA scales a Deployment's replica count up and down automatically based on observed metrics — CPU and memory by default, with custom metrics also possible. It requires **metrics-server** running in the cluster; without it HPA can't read utilization and just sits idle.

HPA is the horizontal scaling approach — more pods. The counterpart is VPA (Vertical Pod Autoscaler) — bigger pods. HPA is the standard choice for stateless workloads.

---

## Install metrics-server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

In a lab cluster with self-signed kubelet certificates, metrics-server needs an extra flag to trust them:

```bash
kubectl -n kube-system patch deployment metrics-server --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

Side benefit: with metrics-server running, `kubectl top` works:

```bash
kubectl top pods
```

```
NAME                           CPU(cores)   MEMORY(bytes)
node-agent-6mb6z               0m           1Mi
node-agent-92sl4               0m           1Mi
notol-pod                      0m           7Mi
pod-with-pvc                   0m           3Mi
rollout-demo-d79786d47-29wl7   0m           2Mi
rollout-demo-d79786d47-gjwmr   0m           2Mi
rollout-demo-d79786d47-qkl7g   0m           2Mi
rollout-demo-d79786d47-v458w   0m           2Mi
tol-pod                        0m           3Mi
web-0                          0m           3Mi
web-2                          0m           3Mi
```

```bash
kubectl top nodes
```

```
NAME          CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k8s-cp1       55m          2%       2207Mi          57%
k8s-worker1   25m          1%       1388Mi          74%
k8s-worker2   28m          1%       1378Mi          73%
```

---

## Deployment

**CPU requests are required for CPU-based HPA.** HPA calculates utilization as `actual CPU / requested CPU`. Without a request, there's no baseline to calculate a percentage against and HPA can't scale.

Create `hpa-demo.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-demo
  labels:
    app: hpa-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hpa-demo
  template:
    metadata:
      labels:
        app: hpa-demo
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          resources:
            requests:
              cpu: 50m
            limits:
              cpu: 100m
```

```bash
kubectl apply -f hpa-demo.yaml
```

---

## Creating the HPA

Imperative:

```bash
kubectl autoscale deployment hpa-demo --cpu-percent=50 --min=2 --max=5
```

Declarative (preferred):

Create `hpa-demo-hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-demo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hpa-demo
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

`autoscaling/v2` is the current API version — it supports CPU, memory, and custom metrics. The older `autoscaling/v1` only supports CPU.

**Key fields:**

| Field | Meaning |
|-------|---------|
| `scaleTargetRef` | The Deployment (or StatefulSet, ReplicaSet) to scale |
| `minReplicas` | Never scale below this — keeps a baseline alive |
| `maxReplicas` | Hard ceiling — prevents runaway scaling |
| `averageUtilization: 50` | Target average CPU across all pods. If pods average above 50%, scale up |

HPA calculates desired replicas as:
```
desiredReplicas = ceil(currentReplicas × (currentUtilization / targetUtilization))
```

Concretely: 2 replicas running, target 50%, current average 80%:
```
ceil(2 × (80 / 50)) = ceil(2 × 1.6) = ceil(3.2) = 4
```

The ratio `currentUtilization / targetUtilization` tells you how overloaded you are (> 1 = over target, < 1 = under target). Multiply by current replicas to get the proportional count needed. `ceil` rounds up — HPA always errs toward more capacity rather than less.

```bash
kubectl apply -f hpa-demo-hpa.yaml
kubectl get hpa hpa-demo
```

```
NAME       REFERENCE             TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 0%/50%   2         5         2          82s
```

---

## Load Test

Expose the Deployment so traffic can reach the pods:

```bash
kubectl expose deployment hpa-demo --port=80
```

Run a load generator:

```bash
kubectl run load-generator --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://hpa-demo; done"
```

**HPA timing behaviour:**
- Polls metrics every **15 seconds**
- Scales **up immediately** once the threshold is crossed
- Scales **down after a 5-minute stabilization window** — prevents flapping when load briefly dips below the threshold

Both can be overridden in the HPA manifest via `behavior.scaleUp` / `behavior.scaleDown`.

After a minute or two:

```bash
kubectl get hpa hpa-demo
```

```
NAME       REFERENCE             TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 58%/50%   2         5         3          5m9s
```

Above 50%, scaled to 3. A little later:

```
NAME       REFERENCE             TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 40%/50%   2         5         4          5m25s
```

Stabilised at 4 pods — CPU is now below 50% with the extra replica absorbing the load.

---

## Cleanup

```bash
kubectl delete pod load-generator
kubectl delete hpa hpa-demo
kubectl delete service hpa-demo
kubectl delete deployment hpa-demo
```
