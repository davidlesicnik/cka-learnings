# Mock Exam 1 — Killer Shell CKA Simulator A

**Date:** 2026-10-08  
**Score:** 65/74 subtasks

---

## Missed subtasks — root cause + fix

### Q1 (1/3) — Contexts / Certificates

**Miss 1:** `/course/1/current-context` wrote `kubernetes-admin` instead of `cluster-w200`
- Don't assume current context — always query it:
```bash
k --kubeconfig /course/1/kubeconfig config current-context > /course/1/current-context
```

**Miss 2:** `/course/1/cert` wrote base64-encoded blob instead of decoded PEM
- Must pipe through `base64 -d`:
```bash
k --kubeconfig /course/1/kubeconfig config view --raw \
  -ojsonpath="{.users[0].user.client-certificate-data}" | base64 -d > /course/1/cert
```
- Result must start with `-----BEGIN CERTIFICATE-----`

---

### Q4 (0/1) — Pods first terminated (QoS)

Find pods with no resource requests = `BestEffort` QoS class:
```bash
k get pods -n project-c13 -o jsonpath="{range .items[*]}{.metadata.name} {.status.qosClass}{'\n'}"
```
Pods with `BestEffort` are evicted first. Write those names to file.

---

### Q5 (5/6) — Kustomize: ConfigMaps not deleted

Removing a resource from kustomization.yaml does NOT delete it from cluster.  
Kustomize is stateless — it only applies what's in YAML, never deletes orphaned resources.  
After `kubectl kustomize ... | kubectl apply -f -`, manually delete:
```bash
k -n api-gateway-staging delete cm horizontal-scaling-config
k -n api-gateway-prod delete cm horizontal-scaling-config
```
Helm DOES track state and would delete automatically.

---

### Q9 (1/2) — K8s API from inside Pod, write secrets to file

Pod existed but output file was wrong/missing.

Steps:
1. Create pod with correct SA: `serviceAccountName: secret-reader` in `namespace: project-swan`
2. Exec in and query:
```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
curl --cacert $CACERT https://kubernetes.default/api/v1/secrets \
  -H "Authorization: Bearer $TOKEN" > result.json
exit
```
3. Copy out:
```bash
k -n project-swan exec api-contact -- cat result.json > /course/9/result.json
```

---

### Q11 (3/4) — DaemonSet wrong image

Used wrong image. Question said `httpd:2-alpine`, not fluentd.  
Always use exact image string from question. Don't conflate with other examples in memory.

DaemonSet toleration to run on controlplane:
```yaml
tolerations:
- effect: NoSchedule
  key: node-role.kubernetes.io/control-plane
```

---

### Q13 (3/5) — HTTPRoute missing /auto header-based routing

HTTPRoute header + path match must be in same `matches` item (AND logic):
```yaml
- matches:
    - path:
        type: PathPrefix
        value: /auto
      headers:                   # same item = AND
      - type: Exact
        name: user-agent
        value: mobile
  backendRefs:
    - name: web-mobile
      port: 80
- matches:
    - path:
        type: PathPrefix
        value: /auto             # catch-all, no header check
  backendRefs:
    - name: web-desktop
      port: 80
```

**Order matters** — mobile rule must come before desktop catch-all.

Wrong (OR logic — breaks matching):
```yaml
- matches:
    - path: ...
    - headers: ...    # separate list item = OR, not AND
```

---

### Q17 (5/6) — pod-container.txt wrong format

File needs both container ID and runtimeType on one line:
```bash
# on worker node:
crictl ps | grep tigers-reunite          # get container ID
crictl inspect <ID> | grep runtimeType   # get runtime
```

Format: `<container_id> <runtimeType>`  
Example: `ba62e5d465ff0 io.containerd.runc.v2`

---

## Key patterns to remember

| Topic | Key point |
|-------|-----------|
| Cert decode | Always `\| base64 -d` when writing cert to file |
| kubeconfig current-context | Query with `config current-context`, never assume |
| QoS / eviction order | BestEffort (no requests) → Burstable → Guaranteed |
| Kustomize vs Helm | Kustomize stateless: orphaned resources need manual `kubectl delete` |
| HTTPRoute AND matching | `path:` and `headers:` in same `-` item = AND; separate `-` items = OR |
| HTTPRoute rule order | More specific rules first, catch-all last |
| crictl pod-container.txt | Format: `<id> <runtimeType>` from `crictl inspect \| grep runtimeType` |
| API from Pod | Token at `/var/run/secrets/kubernetes.io/serviceaccount/token`, CA at same dir |
