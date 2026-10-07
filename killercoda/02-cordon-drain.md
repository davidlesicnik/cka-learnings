# Killercoda: Cordon and Drain

Source: https://killercoda.com/chadmcrowell/course/cka

Scenario: **Cordon and Drain the Node** + **Cordon and Select Node**

---

## Run Notes

### Run 1 — 45s

`kubectl cordon node01` → `kubectl drain node01` failed (DaemonSets present) → reran with `--ignore-daemonsets`. Verified no pods on the node with `kubectl get pods -o wide -A | grep node01`. Finished with `kubectl uncordon node01`.
