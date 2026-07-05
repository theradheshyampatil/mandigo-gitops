# ArgoCD app-of-apps

These manifests make the ArgoCD `Application` objects part of Git instead of
one-off `argocd app create` commands that live only in the cluster. The repo
is now genuinely the single source of truth.

```
k8s/argocd/
├── app-of-apps.yaml          # the ONE app you apply by hand; manages the rest
└── applications/
    ├── mandigo-backend-api.yaml
    ├── mandigo-frontend.yaml
    ├── mandigo-database.yaml   # prune disabled — never auto-delete the DB
    └── mandigo-monitoring.yaml
```

## Adopting on the existing cluster (safe, no downtime)

The four child specs match the apps already running, so ArgoCD adopts them by
name rather than recreating anything.

```bash
kubectl apply -f k8s/argocd/app-of-apps.yaml
```

Then in the ArgoCD UI you'll see a new `mandigo-root` app whose children are
the four existing apps. The only behavioral change: `mandigo-backend-api`
flips from automated-sync **disabled** to **enabled**, which clears its
long-standing `OutOfSync` status on the next push.

## Bootstrap on a brand-new cluster

Install ArgoCD, then the single `kubectl apply` above pulls in everything.

## Sync policy rationale

| App        | prune | selfHeal | why                                             |
|------------|-------|----------|-------------------------------------------------|
| backend    | ✅    | ✅       | CI bumps the image tag; drift should self-heal  |
| frontend   | ✅    | ✅       | same                                            |
| database   | ❌    | ✅       | never let a bad sync prune the PVC/StatefulSet  |
| monitoring | ✅    | ✅       | Helm-managed stack; safe to reconcile fully     |
