# Exercise: Application Unreachable

## Task

Namespace `prod` has a running deployment but the application is not reachable. There are two separate faults. Find and fix both.

1. Pod `api` is Running but `api-svc` has no endpoints — fix the service
2. After fixing the service, a test pod still cannot reach `api-svc` — fix the network policy
3. Verify end-to-end: `curl` from `test-client` to `api-svc` returns HTTP 200
4. Write `fixed` to `/opt/answers/q19.txt`

---

## Setup

```bash
kubectl create namespace prod

# Deployment — label: app=api
kubectl create deployment api -n prod --image=nginx:alpine --port=80

# Service — WRONG selector: app=backend (should be app=api)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: api-svc
  namespace: prod
spec:
  selector:
    app: backend
  ports:
    - port: 80
      targetPort: 80
EOF

# NetworkPolicy — only allows ingress from role=frontend
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: frontend
EOF

# Test client — label: role=client (NOT role=frontend — blocked by NetworkPolicy)
kubectl run test-client -n prod --image=busybox --labels="role=client" \
  -- sh -c "sleep 3600"
```

---

## Reference Solution

```bash
# 1. Diagnose service — check endpoints
kubectl get endpoints api-svc -n prod
# ADDRESS column empty — selector mismatch

kubectl describe svc api-svc -n prod | grep Selector
# Selector: app=backend

kubectl get pods -n prod --show-labels | grep api
# Labels: app=api

# Fix: patch the service selector
kubectl patch svc api-svc -n prod -p '{"spec":{"selector":{"app":"api"}}}'

# Verify endpoints populated
kubectl get endpoints api-svc -n prod

# 2. Diagnose connectivity from test-client
kubectl exec test-client -n prod -- wget -qO- http://api-svc
# wget: bad address — or timeout

kubectl get networkpolicy -n prod
kubectl describe networkpolicy api-ingress -n prod
# Allows ingress from: role=frontend
# test-client has: role=client — BLOCKED

# Fix: update NetworkPolicy to allow role=client
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: client
EOF

# 3. Verify
kubectl exec test-client -n prod -- wget -qO- http://api-svc
# Returns nginx HTML — success

# 4. Write answer
echo "fixed" > /opt/answers/q19.txt
```

---

## Tips

**Empty endpoints = selector mismatch.** `kubectl get endpoints <svc>` is the fastest check. If ADDRESS is empty, the service selector doesn't match any pod labels. Cross-check with `kubectl get pods --show-labels`.

**`kubectl patch` for single-field fixes.** Faster than `kubectl edit` when you know exactly what to change. JSON patch format: `-p '{"spec":{"selector":{"key":"value"}}}'`.

**NetworkPolicy is invisible until it blocks something.** Always check `kubectl get networkpolicy -n <ns>` when connectivity fails but pods and services look correct. The `describe` output shows the full ingress/egress rules.

**Diagnosis order for "app unreachable":**
1. `kubectl get pods` — is it Running?
2. `kubectl get endpoints <svc>` — are endpoints populated?
3. `kubectl exec <test-pod> -- wget/curl <svc>` — does traffic reach the pod?
4. `kubectl get networkpolicy` — is traffic being blocked?
5. `kubectl describe pod` → Events — any other issues?

**`wget -qO-` in busybox** = quiet mode, output to stdout. Equivalent to `curl -s` when curl isn't available.

---

## Run Notes

