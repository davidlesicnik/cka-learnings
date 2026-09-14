# DaemonSets

A DaemonSet ensures **exactly one pod runs on each node** in the cluster. There's no `replicas` field — the pod count is dictated directly by the number of nodes. Add a node, a pod appears; remove a node, a pod disappears.

---

## When to Use DaemonSets

DaemonSets are for node-level concerns — things that need to run on every node:

| Use case | Example |
|----------|---------|
| CNI plugins | Calico's `calico-node` runs as a DaemonSet |
| Log collection | Fluentd/Filebeat shipping node logs |
| Monitoring agents | Prometheus node-exporter, Datadog agent |
| Storage drivers | CSI node plugins |
| kube-proxy | Kubernetes itself runs kube-proxy as a DaemonSet |

The pattern: if it needs to see every node's filesystem, network, or hardware — DaemonSet.

## DaemonSet vs Deployment

| | Deployment | DaemonSet |
|---|-----------|-----------|
| Pod count | Controlled by `replicas` | One per node (automatic) |
| Scheduling | Scheduler picks nodes | Guaranteed on every (eligible) node |
| Scaling | Manual or HPA | Follows node count |
| Use case | Application workloads | Node-level infrastructure |

---

## Creating a DaemonSet

Create `node-agent.yaml`:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  labels:
    app: node-agent
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "while true; do sleep 3600; done"]
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
```

The manifest looks almost identical to a Deployment — same `selector`, same `template`. The only structural difference: no `replicas` field and `kind: DaemonSet`.

Setting `resources.requests` is good practice for DaemonSets since they run on every node — you want predictable resource usage so they don't starve actual workloads.

```bash
kubectl apply -f node-agent.yaml
```

### Verify

```bash
kubectl get daemonset node-agent
```

```
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
node-agent   2         2         2       2            2           <none>          7s
```

Exactly 2 pods — one per worker node. The control plane node doesn't get one because it has a `NoSchedule` taint by default. DaemonSets respect taints unless you add a matching toleration.

```bash
kubectl get pods -o wide
```

```
NAME                           READY   STATUS    RESTARTS   AGE     IP              NODE          NOMINATED NODE   READINESS GATES
node-agent-6mb6z               1/1     Running   0          43s     10.244.194.89   k8s-worker1   <none>           <none>
node-agent-92sl4               1/1     Running   0          43s     10.244.126.27   k8s-worker2   <none>           <none>
```

One pod per worker, as expected.

### Running on the control plane too

To schedule on the control plane (like Calico does), add a toleration to the pod template:

```yaml
spec:
  template:
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule
```

This tells the scheduler: "I'm allowed to run on nodes with this taint." Without it, the control plane's `NoSchedule` taint repels the DaemonSet pod.

---

## Updates

DaemonSets support rolling updates just like Deployments. The default strategy is `RollingUpdate` — pods are updated one node at a time. You can also set `type: OnDelete`, which only updates a pod when you manually delete it (useful for critical infrastructure where you want full control over the rollout).
