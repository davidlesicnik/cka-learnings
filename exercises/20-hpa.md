# Exercise: Horizontal Pod Autoscaler

## Task

1. Create a Deployment `web` in namespace `autoscale` with 1 replica using `nginx:alpine`, with CPU request of `100m` and CPU limit of `200m`.

2. Create an HPA named `web-hpa` that:
   - Targets the `web` deployment
   - Scales between **2** and **6** replicas
   - Targets **50% CPU utilization**

3. Verify the HPA is created and shows current/target replicas.

4. Manually scale the deployment to 4 replicas and confirm the HPA reports the correct current count.

5. Write the min and max replica count of the HPA (format: `min=2 max=6`) to `/opt/answers/q18.txt`.

---

## Reference Solution

```bash
kubectl create namespace autoscale

# 1. Deployment with resource requests
kubectl create deployment web -n autoscale --image=nginx:alpine --replicas=1
kubectl set resources deployment web -n autoscale \
  --requests=cpu=100m --limits=cpu=200m

# 2. HPA
kubectl autoscale deployment web -n autoscale \
  --cpu-percent=50 --min=2 --max=6

# 3. Verify
kubectl get hpa -n autoscale
kubectl describe hpa web-hpa -n autoscale

# HPA immediately scales to min=2 since current=1 < min
kubectl get pods -n autoscale

# 4. Manual scale (HPA overrides this if load drops, but count shows correctly)
kubectl scale deployment web -n autoscale --replicas=4
kubectl get hpa -n autoscale

# 5. Write answer
echo "min=2 max=6" > /opt/answers/q18.txt
```

---

## Tips

**CPU requests are required for HPA to work.** Without `resources.requests.cpu`, the HPA can't compute utilization percentage — it will show `<unknown>/50%`. Always set requests on the target deployment.

**`kubectl autoscale` is the fast path.** No YAML needed for basic CPU-based HPA. Use dry-run to see the manifest if you need to tweak it.

**HPA enforces min replicas immediately.** If the deployment has fewer replicas than `--min`, HPA scales it up right away — no load needed.

**`kubectl get hpa` columns:** `REFERENCE`, `TARGETS` (current%/target%), `MINPODS`, `MAXPODS`, `REPLICAS`. If TARGETS shows `<unknown>`, metrics-server isn't running or requests aren't set.

**Metrics server must be installed** for HPA to function. On the exam cluster it will be. If you see `unable to get metrics`, check with `kubectl top pods` — if that also fails, metrics-server is the issue.

**Manual scale + HPA:** Manual `kubectl scale` works, but HPA will override it on the next sync cycle based on load. In the exam, if HPA is active, use `kubectl edit hpa` to change bounds rather than scaling the deployment directly.

---

## Run Notes

### Run 1 — 4m50s

Straightforward once found `kubectl autoscale deployment` — that's the command, not `kubectl create hpa`. `--help` shows it.
