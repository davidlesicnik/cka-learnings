# Exercise: Init Container + Sidecar Log Shipper

## Task

Create a Pod `app` in namespace `logging` with the following spec:

- An **init container** named `seed` using `busybox` that writes the string `app started` to `/var/log/app/start.log` and exits
- A **main container** named `web` using `nginx:alpine` that mounts the same log directory at `/var/log/app`
- A **sidecar container** named `log-shipper` using `busybox` that tails `/var/log/app/start.log` indefinitely and prints to stdout

Verify:
1. `kubectl logs app -c log-shipper` shows `app started`
2. `kubectl logs app -c seed` shows the init container ran and completed
3. Pod shows `2/2` running containers (not 3 — init containers don't count after they complete)

Write the node the pod is running on to `/opt/answers/q9.txt`.

---

## Reference Solution

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: logging
spec:
  initContainers:
    - name: seed
      image: busybox
      command: ["sh", "-c", "echo 'app started' > /var/log/app/start.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
    - name: log-shipper
      image: busybox
      command: ["sh", "-c", "tail -f /var/log/app/start.log"]
      restartPolicy: Always
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
  containers:
    - name: web
      image: nginx:alpine
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
  volumes:
    - name: logs
      emptyDir: {}
```

```bash
kubectl create namespace logging
kubectl apply -f app.yaml
kubectl get pod app -n logging
kubectl logs app -n logging -c log-shipper
kubectl logs app -n logging -c seed
kubectl get pod app -n logging -o wide | awk 'NR==2{print $7}' > /opt/answers/q9.txt
```

---

## Tips

**Init order matters.** `seed` runs first and exits, then `log-shipper` starts (and stays running because `restartPolicy: Always`), then `web` starts. If `seed` fails, `log-shipper` never starts.

**`restartPolicy: Always` on an initContainer = sidecar.** Without it, `tail -f` would block and the pod would hang in `Init` forever — kubelet waits for each init container to exit before proceeding.

**`2/2` not `3/2`.** Init containers (including sidecars defined in `initContainers`) don't count in the READY column after they transition. The sidecar counts because it stays running. `seed` doesn't because it exited.

**Both init containers share the volume.** `seed` writes, `log-shipper` reads — both run before `web` starts, so the file exists by the time nginx is live.

**Dry-run doesn't help here.** No imperative command generates init container YAML. You write it from scratch or find it in the docs: search "init containers" → "Configure Pod Initialization".

---

## Run Notes

### Run 1 — 8 minutes

Two apply errors before it worked:

**Error 1:** `cannot unmarshal object into Go struct field Container.spec.initContainers.volumeMounts of type []v1.VolumeMount` — missing `-` before the volumeMount entry in an init container. YAML list item needs the dash.

**Error 2:**
```
spec.containers[0].volumeMounts[0].name: Not found: "log"
spec.initContainers[0].volumeMounts[0].name: Not found: "log"
spec.initContainers[1].volumeMounts[0].name: Not found: "log"
```
Added `volumeMounts` to all containers but forgot to define the `volumes:` block at the pod level. Volume must be declared under `spec.volumes` before containers can mount it.

Docs: "Sidecar Containers" page had almost exactly this solution — `restartPolicy: Always` in an initContainer is shown there.
