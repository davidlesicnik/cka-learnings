# Killercoda: Kustomize

Source: https://killercoda.com/chadmcrowell/course/cka

Scenarios (do all 5):
- **Kustomize Apply** - Part 1
- **Kustomize Common Labels** - Part 2
- **Kustomize Configmap Secret** - Part 3
- **Kustomize Env Overlay** - Part 4
- **Kustomize Patch Image** - Part 5

---

## Run Notes

### Run 1 — Part 1: 7m20s, Part 2: 3m35s, Part 3: 6m, Part 4: 3m45s, Part 5: 1m50s

Used `kubectl kustomize .` throughout as a feedback loop to verify each change.

- Part 1: Base + overlay scaffolding from scratch — slowest part, getting the structure right
- Part 2: Faster once scaffolding was familiar
- Part 3: Took a moment to realize ConfigMap injection into a pod needs `envFrom`, not `env`
- Part 4: First multi-overlay exercise, also used to practice `replicas:` syntax
- Part 5: Single image tag override — trivial at this point

Re-scaffolding the base for every part was tedious but good muscle memory for the structure.
