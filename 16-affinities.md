# Affinities

Kubernetes has two affinity types, each with an anti-affinity counterpart:

- **Node affinity** — constrains which nodes a pod can be scheduled on, based on node labels
- **Pod affinity / anti-affinity** — constrains scheduling based on the labels of pods already running on nodes, allowing you to co-locate or isolate workloads

For example: with node affinity you can constrain pods to only schedule on GPU nodes for AI processing. With pod anti-affinity you can isolate heavy backend processing from user-facing frontend, so the frontend won't slow down when the backend is under load.

---

## Enforcement Levels

Affinity rules fall into two enforcement levels:

| Level | Field | Behaviour |
|-------|-------|-----------|
| **Hard** (`required`) | `requiredDuringSchedulingIgnoredDuringExecution` | Mandatory. Pod stays `Pending` if the criteria aren't met |
| **Soft** (`preferred`) | `preferredDuringSchedulingIgnoredDuringExecution` | Best effort. Scheduler scores nodes and picks the highest-ranked option, even if it goes against the preference |

Both types share the same two enforcement levels — you can mix hard and soft rules in the same affinity block.

The `IgnoredDuringExecution` suffix on both means: once a pod is running, if the node's labels change and the rule would no longer match, the pod is **not evicted**. The rule only affects scheduling, not running pods.

The counterpart — `RequiredDuringSchedulingRequiredDuringExecution` — would evict running pods if the node they're on stops satisfying the rule. This field is planned but **not yet implemented** in Kubernetes. Currently `IgnoredDuringExecution` is the only option available for both hard and soft rules.

---

## Node Affinity

Replaces `nodeSelector` with a richer set of expression operators: `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt`.

There is no separate "node anti-affinity" — `NotIn` and `DoesNotExist` already cover it. Pod affinity needs a dedicated anti-affinity field because it's a runtime lookup ("find nodes where pod X is running"), and attract vs. repel can't be expressed with a single operator.

Example manifest combining a hard rule and a soft rule:

```yaml
spec:
  affinity:
    nodeAffinity:
      # HARD RULE: Must be on high-performance infrastructure
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node.kubernetes.io/instance-type
            operator: In
            values:
            - c6i.2xlarge
            - c6i.4xlarge
      # SOFT RULE: Prefer dedicated GPU nodes if available
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 80
        preference:
          matchExpressions:
          - key: gpu
            operator: Exists
```

Hard rule: node instance type **must** be `c6i.2xlarge` or `c6i.4xlarge`. Pod won't schedule elsewhere.

Soft rule: if GPU nodes (with a `gpu` label) are available, prefer them (weight 80 out of 100). If no GPU nodes exist, fall back to any node that satisfies the hard rule.

The `weight` field (1–100) lets you express relative preference when multiple soft rules exist — the scheduler adds up the weights of all matching preferences and picks the highest-scoring node.

---

## Pod Affinity

Schedules a pod onto a node where existing pods matching a label selector are already running. Useful for co-locating services that benefit from proximity (e.g. a service and its local cache).

Example with a hard rule that deploys only onto nodes already holding Redis cache pods:

```yaml
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - redis-cache
        topologyKey: kubernetes.io/hostname  # Co-locate on the exact same node
```

The `topologyKey` defines the scope of "same location." Using `kubernetes.io/hostname` means "same physical node." Using `topology.kubernetes.io/zone` would mean "same availability zone."

---

## Pod Anti-Affinity

Opposite of pod affinity — prevents a pod from scheduling onto nodes where matching pods are already running. Used to spread replicas for high availability.

Example with both a hard and soft rule:

```yaml
spec:
  affinity:
    podAntiAffinity:
      # HARD RULE: Never run two replicas of 'web' on the same physical node
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - web-frontend
        topologyKey: kubernetes.io/hostname  # Targets nodes
      
      # SOFT RULE: Prefer spreading replicas across distinct Availability Zones
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - web-frontend
          topologyKey: topology.kubernetes.io/zone  # Targets AZs
```

Hard rule: never schedule this pod on a node that already has a `web-frontend` pod. Guarantees no two replicas of the same service share a node.

Soft rule: prefer spreading replicas across distinct availability zones. If zones aren't available or already saturated, fall back — it's best effort.

---

## Things to Note

**`topologyKey` is an easy mistake.** Use `kubernetes.io/hostname` for node-level topology and `topology.kubernetes.io/zone` for AZ-level. Getting them swapped is silent — the rule still applies, just at the wrong granularity.

**Hard rules increase scheduler cost.** The scheduler must evaluate each node against the rule. At scale (hundreds of nodes, many pods), over-constrained hard rules become a bottleneck.

**Deadlocks with hard rules.** Over-constraining can leave pods permanently `Pending` if their conditions can never be satisfied — for example, requiring GPU nodes when none exist in the cluster. Always verify that sufficient nodes exist to satisfy hard rules before applying them to production workloads.
