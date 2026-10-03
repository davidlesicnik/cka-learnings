# Static Pods

We've already touched on static pods in earlier exercises — let's go deeper.

A static pod is managed directly by the kubelet *on a single node*, bypassing the API server and scheduler entirely. The kubelet watches a directory on disk (`/etc/kubernetes/manifests/`) and starts, stops, or restarts pods based purely on the YAML files it finds there.

The manifest directory is configured via `staticPodPath` in the kubelet config — if you're ever unsure of the path on a node:

```bash
grep staticPodPath /var/lib/kubelet/config.yaml
```

```
staticPodPath: /etc/kubernetes/manifests
```

This is exactly how control plane components run — kube-apiserver, etcd, kube-scheduler, and kube-controller-manager are all static pods. It's why fixing them requires editing manifests on disk rather than using `kubectl`.

---

## Creating a Static Pod

Drop a manifest directly into `/etc/kubernetes/manifests/` — don't `kubectl apply` it:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-demo
spec:
  containers:
    - name: nginx
      image: nginx:alpine
```

Wait up to a minute for the kubelet to pick it up:

```bash
kubectl get pods -A | grep static-demo
```

```
default   static-demo-k8s-cp1   1/1   Running   0   18s
```

Note the `-k8s-cp1` suffix — the kubelet automatically appends the node hostname. This is a reliable tell that something is a static pod rather than a scheduler-managed one.

---

## Deleting a Static Pod

`kubectl delete` won't work. The pod disappears from the API briefly, then immediately comes back:

```bash
kubectl delete pod static-demo-k8s-cp1
```

```
pod "static-demo-k8s-cp1" deleted from default namespace
```

```bash
kubectl get pods -A | grep static-demo
```

```
default   static-demo-k8s-cp1   1/1   Running   0   3s
```

What actually happens: `kubectl delete` removes the API server's mirror object for the pod, but the pod itself never stopped running. Kubelet detects the manifest is still there and re-registers it.

To actually delete it, remove the manifest:

```bash
sudo rm /etc/kubernetes/manifests/static-demo.yaml
kubectl get pods -A | grep static-demo
# (no output)
```

---

## Troubleshooting Static Pods

Recreate with a broken image tag:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-demo
spec:
  containers:
    - name: nginx
      image: nginx:this-tag-does-not-exist
```

```bash
kubectl get pods -A | grep static-demo
```

```
default   static-demo-k8s-cp1   0/1   ErrImagePull   0   8s
```

The temptation is to `kubectl edit` it — the editor opens and lets you make changes, but the edits are **silently ignored**. kubectl can read static pods (the API has a mirror copy) but cannot modify them.

Fix by editing the manifest on disk directly:

```bash
sudo vi /etc/kubernetes/manifests/static-demo.yaml
# fix the image tag
```

Kubelet detects the change and restarts the pod with the corrected spec. This is the same mechanism used to fix broken control plane components — as in the kube-apiserver drill.
