# Troubleshooting Drills — Part 1

Structured break-and-fix scenarios. Each follows the same pattern: introduce the fault, identify it, fix it.

General first-pass diagnostic workflow:
1. `kubectl get pods` — what's the status?
2. `kubectl describe pod <name>` — check Events at the bottom
3. `kubectl logs <name>` — check application output (if the container started)
4. `journalctl -u kubelet` — node-level issues (if the pod never started)

---

## Drill 1: Bad Image Name / Tag

### Setup

Create `bad-image-demo.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-image-demo
spec:
  containers:
    - name: app
      image: nginx:this-tag-does-not-exist
```

```bash
kubectl apply -f bad-image-demo.yaml
```

### Symptoms

```bash
kubectl get pods
```

```
NAME             READY   STATUS         RESTARTS   AGE
bad-image-demo   0/1     ErrImagePull   0          10s
```

After a minute or two it transitions to `ImagePullBackOff` — Kubernetes backs off exponentially between retries rather than hammering the registry. `ErrImagePull` = active pull attempt failed; `ImagePullBackOff` = waiting before the next attempt.

### Diagnosis

```bash
kubectl describe pod bad-image-demo
```

```
Events:
  Warning  Failed     14s (x2 over 29s)  kubelet  Failed to pull image "nginx:this-tag-does-not-exist": not found
  Warning  Failed     14s (x2 over 29s)  kubelet  Error: ErrImagePull
  Normal   BackOff    3s (x2 over 28s)   kubelet  Back-off pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     3s (x2 over 28s)   kubelet  Error: ImagePullBackOff
```

Events make it clear: the tag doesn't exist on the registry.

### Fix

Correct the image tag in the manifest and re-apply.

---

## Drill 2: Service Unreachable (Selector Mismatch)

### Setup

Create `broken-svc-demo.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broken-svc-demo
  labels:
    app: broken-svc-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: broken-svc-demo
  template:
    metadata:
      labels:
        app: broken-svc-demo
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
---
apiVersion: v1
kind: Service
metadata:
  name: broken-svc
spec:
  selector:
    app: wrong-label
  ports:
    - port: 80
      targetPort: 80
```

The service selector (`app: wrong-label`) doesn't match the deployment's pod labels (`app: broken-svc-demo`).

```bash
kubectl apply -f broken-svc-demo.yaml
```

### Symptoms

```bash
kubectl run tmp --rm -it --image=busybox --restart=Never -- wget -qT 3 -O- broken-svc
```

```
wget: can't connect to remote host (10.102.86.37): Connection refused
```

### Diagnosis

```bash
kubectl describe svc broken-svc
```

```
Selector:    app=wrong-label
Endpoints:
```

Empty `Endpoints` is the key signal — the service exists but has no pods to route to. You can also check directly:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=broken-svc
```

```
NAME               ADDRESSTYPE   PORTS   ENDPOINTS   AGE
broken-svc-xxxxx   IPv4          80      <none>      2m
```

Compare against the deployment's labels:

```bash
kubectl describe deploy broken-svc-demo | grep Labels
```

```
Labels:  app=broken-svc-demo
```

`app=wrong-label` vs `app=broken-svc-demo` — mismatch confirmed.

### Fix

Edit the service selector to match the pod labels:

```yaml
spec:
  selector:
    app: broken-svc-demo
```

Once applied, `kubectl get endpoints broken-svc` should show pod IPs.

## Drill 3: Broken Kubelet (Can't Reach API Server)

### Setup

Shell into a worker node and corrupt the API server port in the kubelet config. Back it up first:

```bash
multipass shell k8s-worker1
```

```bash
sudo cp /etc/kubernetes/kubelet.conf /root/kubelet.conf.bak
sudo sed -i 's/:6443/:6444/' /etc/kubernetes/kubelet.conf
sudo systemctl restart kubelet
```

### Symptoms

Wait a minute, then check from the **control plane**:

```bash
kubectl get nodes
```

```
NAME          STATUS     ROLES           AGE   VERSION
k8s-cp1       Ready      control-plane   39d   v1.36.3
k8s-worker1   NotReady   <none>          39d   v1.36.3
k8s-worker2   Ready      <none>          39d   v1.36.3
```

`worker1` dropped out — kubelet is running but can't reach the API server.

### Diagnosis

On the worker node, check the kubelet service:

```bash
sudo systemctl status kubelet
```

```
● kubelet.service - kubelet: The Kubernetes Node Agent
     Active: active (running) since Mon 2026-09-28 09:58:30 CEST; 2min 58s ago
     ...
Sep 28 10:01:27 k8s-worker1 kubelet[786675]: "Unable to register mirror pod because node is not registered yet" node="k8s-worker1"
Sep 28 10:01:28 k8s-worker1 kubelet[786675]: "Unable to register mirror pod because node is not registered yet" node="k8s-worker1"
```

`active (running)` is misleading — kubelet is up as a process, but that says nothing about whether it can talk to the API server. The "node not registered" spam is a **symptom**, not the root cause. Dig deeper with journalctl:

```bash
sudo journalctl -u kubelet --no-pager
```
Among the spam:
```
E0928 10:02:41 kubelet[786675]: "Unable to register node with API server" err="Post \"https://192.168.252.2:6444/api/v1/nodes\": dial tcp 192.168.252.2:6444: connect: connection refused" node="k8s-worker1"
```

Root cause: kubelet is trying to reach `192.168.252.2:6444` — wrong port. Confirm the correct one from the control plane:

```bash
kubectl cluster-info
```

```
Kubernetes control plane is running at https://192.168.252.2:6443
```

### Fix

On the worker node:

```bash
sudo vi /etc/kubernetes/kubelet.conf
# change :6444 back to :6443
sudo systemctl restart kubelet
```

`worker1` rejoins the cluster within ~30 seconds.

### Key takeaway

`systemctl status kubelet` showing `active` does not mean kubelet is healthy — it only means the process is running. Always check `journalctl -u kubelet` for the actual errors. Look for the root cause log line (`Unable to register node`), not the downstream symptom spam (`mirror pod not registered`).

## Drill 4: Crashed Control Plane Component (kube-apiserver)

kube-apiserver is the most impactful component to break — `kubectl` itself stops working, so the normal diagnostic tools are unavailable. This drill covers how to troubleshoot without them.

### Setup

On the control plane node, back up then break the kube-apiserver static pod manifest by pointing it at etcd's peer port instead of the client port:

```bash
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
sudo sed -i 's#127.0.0.1:2379#127.0.0.1:2380#' /etc/kubernetes/manifests/kube-apiserver.yaml
```

kubelet detects the manifest change and restarts the static pod automatically.

### Symptoms

```bash
kubectl get nodes
```

```
The connection to the server 192.168.252.2:6443 was refused - did you specify the right host or port?
```

`kubectl` is dead — the API server isn't responding.

### Diagnosis

`kubectl` is unavailable, so work directly on the node. Check kubelet:

```bash
sudo systemctl status kubelet
```

Service is running, but logs are full of downstream noise (same misleading `active` situation as drill 3). Move straight to the pod logs.

Control plane static pod logs live in `/var/log/pods/`:

```bash
ls /var/log/pods/ | grep apiserver
```

```
kube-system_kube-apiserver-k8s-cp1_c7bb1cbb5774bceb41059456591f1dcb
```

Read the latest log file inside that directory:

```bash
cat /var/log/pods/kube-system_kube-apiserver-k8s-cp1_c7bb1cbb5774bceb41059456591f1dcb/kube-apiserver/5.log
```

```
grpc: addrConn.createTransport failed to connect to {Addr: "127.0.0.1:2380"}. Err: connection error: dial tcp 127.0.0.1:2380: connect: connection refused
```

kube-apiserver is trying to connect to etcd on port `2380`. Confirm the correct etcd client port from the etcd manifest:

```bash
grep listen-client-urls /etc/kubernetes/manifests/etcd.yaml
```

```
--listen-client-urls=https://127.0.0.1:2379,https://192.168.252.2:2379
```

etcd listens for clients on `2379`. Port `2380` is the peer port (etcd cluster communication) — wrong target.

### Fix

```bash
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
# find --etcd-servers=https://127.0.0.1:2380
# change 2380 → 2379
```

kubelet picks up the change automatically. Wait ~1 minute:

```bash
kubectl get nodes
```

```
NAME          STATUS   ROLES           AGE   VERSION
k8s-cp1       Ready    control-plane   39d   v1.36.3
k8s-worker1   Ready    <none>          39d   v1.36.3
k8s-worker2   Ready    <none>          39d   v1.36.3
```

### Key takeaway

When `kubectl` is dead, the diagnostic path is: **`/var/log/pods/`** for static pod logs, and **`/etc/kubernetes/manifests/`** for static pod config. These are always available on the node regardless of API server state. Cross-reference broken config against the other component manifests (e.g. etcd manifest) to find the mismatch.
