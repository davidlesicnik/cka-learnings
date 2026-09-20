# ConfigMaps and Secrets

ConfigMaps hold non-sensitive configuration data. Secrets hold sensitive data (credentials, tokens, keys) and are base64-encoded — **not encrypted**. Base64 is just an encoding scheme; anyone with access to the secret object can decode it instantly. Kubernetes treats secrets differently at the API level (omits values from logs, restricts `watch` access), but the data itself is not protected at rest unless you configure etcd encryption separately.

| | ConfigMap | Secret |
|--|-----------|--------|
| **Purpose** | Non-sensitive config | Sensitive data |
| **Storage** | Plain text | Base64-encoded |
| **Encryption at rest** | No | No (unless etcd encryption enabled) |
| **API protections** | None | Values redacted from logs, restricted watch |
| **`type` field** | N/A | `Opaque` (generic), or specialised types (`kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`, etc.) |

Both can be consumed in two ways:

| Method | How it works | Updates live? |
|--------|-------------|---------------|
| **Environment variable** | Baked in at container start | No — pod must restart |
| **Volume mount** | File on the pod's filesystem | Yes — Kubernetes updates the file without restart |

---

## Creating ConfigMap and Secret

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=LOG_LEVEL=debug

kubectl create secret generic app-secret \
  --from-literal=DB_PASSWORD=supersecret123
```

Inspect both:

```bash
kubectl get configmap app-config -o yaml
```

```yaml
apiVersion: v1
data:
  APP_MODE: production
  LOG_LEVEL: debug
kind: ConfigMap
metadata:
  creationTimestamp: "2026-09-20T08:25:12Z"
  name: app-config
  namespace: default
  resourceVersion: "3193585"
  uid: e61c32f0-42fe-4e28-a8f7-9e256fc6fd0b
```

```bash
kubectl get secret app-secret -o yaml
```

```yaml
apiVersion: v1
data:
  DB_PASSWORD: c3VwZXJzZWNyZXQxMjM=
kind: Secret
metadata:
  creationTimestamp: "2026-09-20T08:25:39Z"
  name: app-secret
  namespace: default
  resourceVersion: "3193645"
  uid: 8d062ab1-9a3c-4426-b322-500016605ec9
type: Opaque
```

The secret value is base64-encoded. Decode it:

```bash
echo "c3VwZXJzZWNyZXQxMjM=" | base64 -d
```

```
supersecret123
```

`type: Opaque` is the generic secret type — it means "arbitrary user-defined data." Kubernetes also has specialised types (`kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`) that enforce a specific key structure.

---

## Consuming Both in a Pod

This pod consumes the ConfigMap as environment variables and the Secret as a mounted volume — both patterns in one manifest:

Create `config-secret-demo.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-secret-demo
spec:
  containers:
    - name: app
      image: nginx:alpine
      envFrom:
        - configMapRef:
            name: app-config
      volumeMounts:
        - name: secret-vol
          mountPath: /etc/secret
          readOnly: true
  volumes:
    - name: secret-vol
      secret:
        secretName: app-secret
```

`envFrom` dumps every key in the ConfigMap as an environment variable. For a single key, use `env.valueFrom.configMapKeyRef` instead. The secret volume creates each key as a separate file under `/etc/secret`.

```bash
kubectl apply -f config-secret-demo.yaml
```

### Verify env vars

```bash
kubectl exec config-secret-demo -- env
```

```
APP_MODE=production
LOG_LEVEL=debug
```

### Verify volume mount

```bash
kubectl exec config-secret-demo -- ls /etc/secret -lah
```

```
total 8K
drwxrwxrwt    3 root     root         100 Sep 20 08:29 .
drwxr-xr-x    1 root     root        4.0K Sep 20 08:29 ..
drwxr-xr-x    2 root     root          60 Sep 20 08:29 ..2026_09_20_08_29_02.1936076747
lrwxrwxrwx    1 root     root          32 Sep 20 08:29 ..data -> ..2026_09_20_08_29_02.1936076747
lrwxrwxrwx    1 root     root          18 Sep 20 08:29 DB_PASSWORD -> ..data/DB_PASSWORD
```

The symlink structure (`DB_PASSWORD -> ..data/DB_PASSWORD -> timestamped-dir/DB_PASSWORD`) is how Kubernetes performs atomic live updates — it swaps the `..data` symlink to a new timestamped directory in one operation, so the pod never reads a half-written file.

```bash
kubectl exec config-secret-demo -- cat /etc/secret/DB_PASSWORD
```

```
supersecret123
```

The value is decoded inside the pod — base64 encoding is only at the storage layer.

---

## Live Update: Env Var (ConfigMap)

Environment variables are baked in at pod start. Updating the ConfigMap does not affect a running pod:

```bash
kubectl edit configmap app-config
# Change LOG_LEVEL: debug → LOG_LEVEL: info
```

```bash
kubectl exec config-secret-demo -- env | grep LOG_LEVEL
```

```
LOG_LEVEL=debug
```

Still `debug`. Restart the pod to pick up the change:

```bash
kubectl delete -f config-secret-demo.yaml
kubectl apply -f config-secret-demo.yaml
kubectl exec config-secret-demo -- env | grep LOG_LEVEL
```

```
LOG_LEVEL=info
```

---

## Live Update: Volume Mount (Secret)

Volume-mounted secrets update live without restarting the pod. Use `kubectl patch` with `stringData` — Kubernetes automatically base64-encodes the value, so you don't have to:

```bash
kubectl patch secret app-secret --type merge -p '{"stringData":{"DB_PASSWORD":"newpassword456"}}'
```

If you use `kubectl edit` instead, you must provide the value already base64-encoded — the interactive editor writes directly to the `data` field, which expects encoded values.

```bash
kubectl exec config-secret-demo -- cat /etc/secret/DB_PASSWORD
```

```
newpassword456
```

Updated live, no pod restart needed.

---

## Cleanup

```bash
kubectl delete -f config-secret-demo.yaml
kubectl delete configmap app-config
kubectl delete secret app-secret
```
