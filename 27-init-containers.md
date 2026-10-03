# Init Containers

Init containers run before a pod's main containers start — sequentially, each one must complete successfully before the next begins. Only after *all* of them complete does the main container start.

Unlike sidecars, init containers run to completion and exit. They're useful for setup tasks: waiting for a dependency, seeding a volume, or running a migration before the app starts.

---

## Basic Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
spec:
  initContainers:
    - name: wait-for-service
      image: busybox
      command: ["sh", "-c", "echo waiting; sleep 10; echo done waiting"]
  containers:
    - name: app
      image: nginx:alpine
```

Watch the pod start:

```bash
kubectl get pod init-demo -w
```

```
NAME        READY   STATUS            RESTARTS   AGE
init-demo   0/1     Init:0/1          0          5s
init-demo   0/1     PodInitializing   0          13s
init-demo   1/1     Running           0          13s
```

`Init:0/1` = first (of one) init container running. `PodInitializing` = init done, main container starting.

### Viewing init container logs

`kubectl logs` defaults to the main container:

```bash
kubectl logs init-demo
```

```
Defaulted container "app" out of: app, wait-for-service (init)
```

Specify the init container explicitly:

```bash
kubectl logs init-demo -c wait-for-service
```

```
waiting
done waiting
```
---

## Volume Sharing

An init container can populate a shared volume that the main container then reads — useful for database migrations, config generation, or data seeding.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-config-demo
spec:
  initContainers:
    - name: setup
      image: busybox
      command: ["sh", "-c", "echo 'config loaded at startup' > /work/ready.txt"]
      volumeMounts:
        - name: shared-data
          mountPath: /work
  containers:
    - name: app
      image: nginx:alpine
      volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: shared-data
      emptyDir: {}
```

`emptyDir` is the key — a volume that starts empty and is shared between containers even though they don't run at the same time. The init container writes to it, exits, and the file persists on the volume for the main container to read.

---

## Failing Init Container

If an init container crashes, the main container never starts — the pod cycles through `Init:CrashLoopBackOff` instead.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-fail-demo
spec:
  initContainers:
    - name: broken-init
      image: busybox
      command: ["sh", "-c", "echo failing; exit 1"]
  containers:
    - name: app
      image: nginx:alpine
```

```bash
kubectl get pods init-fail-demo -w
```

```
NAME             READY   STATUS                  RESTARTS     AGE
init-fail-demo   0/1     Init:CrashLoopBackOff   1 (7s ago)   10s
```

Diagnose the same way as a regular CrashLoopBackOff: `kubectl describe pod` for events, `kubectl logs -c broken-init` (or `--previous`) for the crash output.

---

## Multiple Init Containers

Multiple init containers run strictly in order — `step-2` won't start until `step-1` exits `0`.

```yaml
initContainers:
  - name: step-1
    image: busybox
    command: ["sh", "-c", "echo step 1; sleep 3"]
  - name: step-2
    image: busybox
    command: ["sh", "-c", "echo step 2; sleep 3"]
```

`kubectl get pod -w` will show `Init:0/2`, then `Init:1/2`, then `PodInitializing` as each step completes.
