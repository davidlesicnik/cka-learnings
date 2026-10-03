# Sidecar Containers

Sidecar containers run *alongside* the main container for the full lifetime of the pod — in contrast to init containers, which run once before the main container starts and then exit.

Common uses: log shippers, config reload watchers, proxy agents (like Envoy in a service mesh), metrics exporters.

---

## Defining a Sidecar

Sidecars are defined under `initContainers` — but with `restartPolicy: Always`. This is the native sidecar pattern introduced in Kubernetes 1.29. The `restartPolicy: Always` is what distinguishes them from regular init containers: instead of running to completion and exiting, they stay running alongside the main container.

The lifecycle implications matter:
- Sidecars start *before* the main containers (because they're in `initContainers`)
- They stay running for the pod's full lifetime
- They're restarted if they crash (because `restartPolicy: Always`)
- Pod shutdown waits for the main container to exit first, then terminates sidecars — so the log shipper won't be killed while the app is still writing logs

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: native-sidecar-demo
spec:
  initContainers:
    - name: log-shipper
      image: busybox
      command: ["sh", "-c", "tail -f /var/log/nginx/access.log"]
      restartPolicy: Always
      volumeMounts:
        - name: logs
          mountPath: /var/log/nginx
  containers:
    - name: app
      image: nginx:alpine
      volumeMounts:
        - name: logs
          mountPath: /var/log/nginx
  volumes:
    - name: logs
      emptyDir: {}
```

Both containers mount the same `emptyDir` volume. nginx writes access logs to `/var/log/nginx/access.log`; the log-shipper tails that file and forwards it to stdout (where a real log shipper would send it upstream).

```bash
kubectl get pods native-sidecar-demo
```

```
NAME                  READY   STATUS    RESTARTS      AGE
native-sidecar-demo   2/2     Running   1 (34s ago)   36s
```

`2/2` — both the app container and the sidecar counted as running containers in the pod.

---

## Init Container vs Sidecar — Quick Comparison

| | Init Container | Sidecar |
|---|---|---|
| Defined under | `initContainers` | `initContainers` (with `restartPolicy: Always`) |
| Runs | Before main container, once | Alongside main container, full pod lifetime |
| Exits | Yes — must exit 0 to proceed | No — stays running |
| Restart on crash | No (pod fails) | Yes |
| Use case | Setup, migrations, seeding | Logging, proxying, watching |
