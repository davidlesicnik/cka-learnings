# Killercoda: Taints and Tolerations

Source: https://killercoda.com/chadmcrowell/course/cka

Scenario: **Taints and Tolerations** + **Add a Toleration to a Pod YAML** + **Remove the Taint from Node**

---

## Run Notes

### Run 1 — Part 1: 2m, Part 2: 2m15s

Part 1: `kubectl describe node controlplane | grep -A10 Labels` to get the label, docs page for toleration YAML format.

Part 2: Took a moment — initially went to add a toleration to the pod, but the task was to remove the taint from the node. `kubectl taint node controlplane <key>:<effect>-` (trailing `-` removes the taint). Got the taint string from `kubectl describe node controlplane | grep Taint`.
