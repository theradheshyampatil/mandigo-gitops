# Secret templates

Real Kubernetes Secrets are **not** stored in this repo. These are fill-in
templates only.

## Why they live here and not next to the manifests

ArgoCD applies **every** `*.yaml` file in an Application's source path,
regardless of the `.example` in the filename. If a secret template (or a
filled-in `secret.yaml`) sits in `k8s/backend/`, `k8s/database/`, or
`k8s/monitoring/`, ArgoCD will apply it and **overwrite the live secret with
the placeholder values**. So all templates live here, under `examples/`, which
no Application watches.

## How to apply a real secret

Copy a template somewhere outside any `k8s/<app>` path, fill it in, and apply:

```bash
cp examples/secrets/backend-mandigo-db-credentials.example.yaml /tmp/be.yaml
# edit /tmp/be.yaml with real values
kubectl apply -f /tmp/be.yaml
rm /tmp/be.yaml
```

| Template | Namespace | Consumed by |
|---|---|---|
| `database-mandigo-db-credentials.example.yaml` | `database` | Postgres StatefulSet (`envFrom`) |
| `backend-mandigo-db-credentials.example.yaml`  | `default`  | Backend Deployment (`DATABASE_URL`, `JWT_SECRET`) |
| `grafana-admin-credentials.example.yaml`       | `monitoring` | Grafana (`admin.existingSecret`) + demo-user Job |

Notes:
- The `database` and `default` secrets share the **name** `mandigo-db-credentials`
  but hold **different keys** (they're in different namespaces).
- `DATABASE_URL`'s user/password must match the `database` secret; URL-encode
  special characters in the password (`!` → `%21`).
