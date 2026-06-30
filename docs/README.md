# MandiGo splash page (GitHub Pages)

The always-on landing page recruiters hit first. Hosted on **GitHub Pages**
(free, always-on, free HTTPS) so it stays reachable even when the EC2 demo
is asleep. The "▶ Wake the project" button calls a Lambda Function URL that
starts the EC2; once it's up, the link grid lights up.

```
demo.projectbyradhe.xyz  (GitHub Pages — ALWAYS ON)
   └─ "▶ Wake the project"  →  Lambda Function URL  →  ec2:StartInstances
        └─ ~2-3 min  →  EC2 live  →  links to /architecture, /monitoring, etc.
   EventBridge cron stops the EC2 ~10 min after the last wake.
```

## One-time GitHub Pages setup

1. **Enable Pages** — in this repo: **Settings → Pages**
   - **Source:** Deploy from a branch
   - **Branch:** `main`  ·  **Folder:** `/docs`
   - Save.
2. Within ~1 min the site is live at
   `https://theradheshyampatil.github.io/mandigo-gitops/`.

### Custom domain `demo.projectbyradhe.xyz`

3. The `docs/CNAME` file already contains `demo.projectbyradhe.xyz`.
4. At **GoDaddy**, add a DNS record:

   | Type | Name | Value |
   |---|---|---|
   | CNAME | `demo` | `theradheshyampatil.github.io` |

5. Back in **Settings → Pages → Custom domain**, it should show
   `demo.projectbyradhe.xyz`. Tick **Enforce HTTPS** once the cert
   provisions (a few minutes).

Then `https://demo.projectbyradhe.xyz` is your always-on recruiter entry point.

## Updating the wake URL

`WAKE_URL` in `index.html` is the Lambda Function URL from
`terraform/wake` (`terraform output wake_function_url`). If you ever
`terraform destroy` + re-apply the wake module, the URL changes — update
the `WAKE_URL` constant in `index.html` and push.

## What it links to

| Tile | URL |
|---|---|
| Marketplace | https://projectbyradhe.xyz |
| Architecture | https://projectbyradhe.xyz/architecture |
| About + Resume | https://projectbyradhe.xyz/about |
| Live monitoring | https://projectbyradhe.xyz/monitoring |
| Raw API | https://api.projectbyradhe.xyz/api/v1/fruits |
| ArgoCD | https://argocd.projectbyradhe.xyz |
