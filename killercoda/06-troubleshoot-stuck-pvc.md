# Killercoda: Troubleshoot a Stuck PVC

Source: https://killercoda.com/chadmcrowell/course/cka

Scenario: **Troubleshoot a Stuck PVC**

---

## Run Notes

### Run 1 — 6m10s

PVC stuck Pending — access mode mismatch: PVC had `RWX`, PV had `RWO`. PVCs are immutable after creation, so: `kubectl edit pvc` to read all current values → grabbed PVC YAML template from "Configure a Pod to Use a PersistentVolume for Storage" docs page → recreated with correct `RWO`. Deleted old PVC, applied new one, pod started automatically.
