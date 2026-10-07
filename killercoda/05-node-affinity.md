# Killercoda: Node Affinity

Source: https://killercoda.com/chadmcrowell/course/cka

Scenario: **Apply node affinity to a pod** + **Node Affinity: Required and Preferred** + **Scheduling a pod to a specific node**

Scenario text:

In the namespace named 012963bd , create a pod named az1-pod which uses the nginx:1.24.0 image. This pod should use node affinity, and prefer during scheduling to be placed on the node with the label availability-zone=zone1 with a weight of 80.

Also, have that same pod prefer to be scheduled to a node with the label availability-zone=zone2 with a weight of 20.

NOTE: Make sure the container remains in a running state
Ensure that the pod is scheduled to the controlplane node.

---

## Run Notes

### Run 1 — 4m10s

Wasted time not reading the full task first — started with `requiredDuringScheduling`, then saw it needed `preferredDuringScheduling` with weights (80 for zone1, 20 for zone2). Also needed a controlplane toleration to get the pod to land there.

Lesson: read the whole task before writing any YAML.
