# kubectl debug

`kubectl debug` creates a throwaway container for situations where normal `exec` won't work: a pod with no shell, a crashed pod, or a node without SSH access.

Three distinct modes depending on what you're trying to reach.

---

## Mode 1: Attach a Container to a Running Pod

Useful when the pod's image has no shell (minimal/distroless images).

```bash
kubectl run minimal-pod --image=nginx:alpine
kubectl debug -it minimal-pod --image=busybox --target=minimal-pod
```

`--target` is critical — it makes the debug container share the process namespace of the target container, so you can see its processes. Without it, you're in an isolated namespace and `ps aux` only shows your own shell.

```bash
/ # ps aux
PID   USER     TIME  COMMAND
    1 root      0:00 nginx: master process nginx -g daemon off;
   30 101       0:00 nginx: worker process
   31 101       0:00 nginx: worker process
   32 root      0:00 sh
   40 root      0:00 ps aux
```

nginx processes visible from inside the busybox debug container.

**Cleanup caveat:** ephemeral containers are append-only. There's no `kubectl delete container`, no patch that removes an entry from `.spec.ephemeralContainers` — that field is explicitly append-only via its own API subresource. The only way to get rid of it is to delete the pod.

For controller-managed pods (Deployment, StatefulSet), this is painless — delete the pod, the controller reschedules a clean replacement. For bare pods, deleting is destructive: the pod is gone entirely, not just the debug container.

Exam implication: if a task says "debug this pod without disrupting it" and it's a bare pod rather than something controller-managed, `--copy-to` (Mode 3) is actually the less disruptive choice — it leaves the original completely untouched and just needs its own cleanup.

---

## Mode 2: Debug a Node Without SSH

Common on managed clusters where SSH access isn't available.

```bash
kubectl debug node/k8s-worker1 --image=busybox -it
```

`kubectl debug` mounts the node's filesystem at `/host`. `chroot` into it to get a full node shell:

```bash
/ # chroot /host
root@k8s-worker1:/# systemctl status kubelet
● kubelet.service - kubelet: The Kubernetes Node Agent
     Active: active (running) since Sat 2026-10-03 09:42:10 CEST; 7min ago
```

**Important:** exiting leaves the debug pod running:

```
Session ended, resume using 'kubectl attach node-debugger-k8s-worker1-5jq2m -c debugger -n default -i -t' command
```

Clean it up manually when done:

```bash
kubectl delete pod node-debugger-k8s-worker1-5jq2m
```

---

## Mode 3: Copy a Pod with a Modified Command

Useful when a pod is CrashLooping too fast to `exec` into, or you want to override the entrypoint to stop it from crashing so you can inspect the environment.

Note: this only helps if the crash is in the application logic. If it's a pod config issue (bad image, wrong volume mount, missing ConfigMap), the copy will have the same problem.

Create a crashing pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: crashy
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh", "-c", "echo 'checking license'; exit 1"]
```

```bash
kubectl get pods
```

```
NAME     READY   STATUS   RESTARTS      AGE
crashy   0/1     Error    2 (22s ago)   26s
```

Copy it with an overridden command:

```bash
kubectl debug crashy --copy-to=crashy-debug --container=app -it -- sh
```

Drops into a shell inside a copy of the pod, with the original crash command replaced by `sh`. The environment, volumes, and config are all the same — just the entrypoint is different, so it stays alive long enough to inspect.
