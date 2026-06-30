# ArgoCD public access (replaces manual port-forward)

Exposes ArgoCD permanently at `https://argocd.projectbyradhe.xyz` so you
never have to run `kubectl port-forward` again, and recruiters can view the
GitOps dashboard with no login (read-only).

## One-time setup

### 1. Put ArgoCD server in insecure mode

ArgoCD's server normally serves its own TLS. To route it through Traefik
(which already terminates Let's Encrypt TLS at the edge), the server must
serve plain HTTP — otherwise you get TLS-in-TLS errors.

```bash
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deploy argocd-server
```

### 2. Enable anonymous read-only access (no login for recruiters)

```bash
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"users.anonymous.enabled":"true"}}'
kubectl -n argocd patch configmap argocd-rbac-cm --type merge \
  -p '{"data":{"policy.default":"role:readonly"}}'
kubectl -n argocd rollout restart deploy argocd-server
```

### 3. DNS — add the GoDaddy A record

| Type | Name | Value | TTL |
|---|---|---|---|
| A | `argocd` | `3.6.157.180` | 600 |

### 4. Apply this IngressRoute

Either apply once with kubectl:
```bash
kubectl apply -f k8s/argocd/ingress.yaml
```

…or (cleaner, fully GitOps) create an ArgoCD Application that watches
`k8s/argocd` — Application name `mandigo-argocd`, path `k8s/argocd`,
namespace `argocd`, auto-sync. Then ArgoCD manages its own ingress.

## Verify

```bash
# Traefik should serve a Let's Encrypt cert (first hit ~10-20s)
curl -sSI https://argocd.projectbyradhe.xyz | head -5
```
Then open `https://argocd.projectbyradhe.xyz` — the app dashboard loads
with no login prompt (anonymous read-only).

## Security note

Anonymous read-only exposes your app names and source repo URLs publicly.
That's intentional for a portfolio (it shows off the GitOps setup) and is
safe — `role:readonly` cannot sync, delete, or change anything. NEVER grant
anonymous more than `role:readonly`.

To revert to the manual port-forward model: delete the IngressRoutes,
set `server.insecure` back to `false`, set `users.anonymous.enabled` to
`false`, restart argocd-server.
