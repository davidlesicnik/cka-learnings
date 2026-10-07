# Exercise: ConfigMap and Secret

## Task

Namespace `config-demo` exists. 

1. Create a ConfigMap named `app-config` with:
   - `APP_ENV=production`
   - `LOG_LEVEL=info`

2. Create a Secret named `db-creds` with:
   - `DB_USER=admin`
   - `DB_PASS=s3cr3t`

3. Create a Pod named `app` using `busybox` that:
   - Mounts `APP_ENV` and `LOG_LEVEL` as environment variables from `app-config`
   - Mounts `DB_USER` as an environment variable from `db-creds`
   - Mounts the entire `db-creds` Secret as a volume at `/etc/db-creds`
   - Runs: `sh -c "env && ls /etc/db-creds && sleep 3600"`

4. Verify the env vars are present and `/etc/db-creds` contains `DB_USER` and `DB_PASS` files.

---

## Reference Solution

```bash
kubectl create namespace config-demo

# 1. ConfigMap
kubectl create configmap app-config -n config-demo \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=info

# 2. Secret
kubectl create secret generic db-creds -n config-demo \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASS=s3cr3t

# 3. Pod — dry-run then edit to add volume + envFrom mix
kubectl run app -n config-demo --image=busybox --dry-run=client -o yaml \
  -- sh -c "env && ls /etc/db-creds && sleep 3600" > pod.yaml
```

Edit `pod.yaml` to add:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: config-demo
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh", "-c", "env && ls /etc/db-creds && sleep 3600"]
      env:
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: APP_ENV
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-creds
              key: DB_USER
      volumeMounts:
        - name: db-secret-vol
          mountPath: /etc/db-creds
          readOnly: true
  volumes:
    - name: db-secret-vol
      secret:
        secretName: db-creds
```

```bash
kubectl apply -f pod.yaml

# 4. Verify
kubectl logs app -n config-demo | grep -E "APP_ENV|LOG_LEVEL|DB_USER"
kubectl exec app -n config-demo -- ls /etc/db-creds
kubectl exec app -n config-demo -- cat /etc/db-creds/DB_USER
```

---

## Tips

**Two injection patterns:** `env[].valueFrom` = single key from ConfigMap/Secret. `envFrom[].configMapRef` = all keys at once as env vars. Know both — exam uses either.

**Secret volume = one file per key.** `/etc/db-creds/DB_USER` and `/etc/db-creds/DB_PASS` become separate files. File content is the raw value (not base64).

**`secretKeyRef` vs `configMapKeyRef`:** Same structure, different field name. Easy to swap by accident.

**`readOnly: true` on secret volumeMount** — good practice, often expected in exam tasks.

**`kubectl create configmap --from-file=`** mounts a whole file as a single key. `--from-literal=` for individual values.

**Secrets are base64 in etcd, plain when mounted.** You never need to base64-encode when using `--from-literal` — kubectl does it.

---

## Run Notes

### Run 1 — 10m20s

Used `--help` for ConfigMap and Secret creation. Had to find that Secrets require `generic` subtype (`kubectl create secret generic`).

For the pod: mixing env vars from ConfigMap + volume mount from Secret in the same pod is the bulk of the YAML. No imperative shortcut — dry-run the base then hand-edit the `env` and `volumes` blocks.
