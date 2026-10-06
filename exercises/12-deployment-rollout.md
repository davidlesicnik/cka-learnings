# Exercise: Deployment Rollout and Rollback

## Task

A Deployment `api` exists in namespace `prod` running `nginx:1.25`. 

1. Update the image to `nginx:1.27` using a rolling update
2. Check rollout history — confirm 2 revisions exist
3. Roll back to revision 1
4. Scale the deployment to 5 replicas
5. Write the current image name to `/opt/answers/q10.txt`

Constraints:
- Do not delete and recreate the deployment
- All 5 replicas must be `Running` at the end

## Setup

```bash
kubectl create namespace prod
kubectl create deployment api -n prod --image=nginx:1.25 --replicas=3
```

---

## Reference Solution

```bash
# 1. Update image
kubectl set image deployment/api nginx=nginx:1.27 -n prod

# 2. Check history
kubectl rollout history deployment/api -n prod

# 3. Roll back to revision 1
kubectl rollout undo deployment/api --to-revision=1 -n prod

# 4. Scale
kubectl scale deployment api -n prod --replicas=5

# 5. Write image
kubectl get deployment api -n prod -o jsonpath='{.spec.template.spec.containers[0].image}' > /opt/answers/q10.txt
```

---

## Tips

**Container name matters for `set image`.** Format is `<container-name>=<image>`. The container name defaults to the image name on creation — `nginx` if created with `--image=nginx:1.25`. Check with `kubectl get deployment api -o yaml | grep name` if unsure.

**`rollout undo` without `--to-revision` goes back one revision.** Use `--to-revision=1` to target a specific one.

**`rollout status` to watch.** `kubectl rollout status deployment/api -n prod` blocks until complete — useful before checking history.

**jsonpath for image.** `{.spec.template.spec.containers[0].image}` — memorize this path, it comes up whenever tasks ask you to extract the image name.

---

## Run Notes

