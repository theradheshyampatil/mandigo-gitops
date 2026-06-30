# MandiGo wake-on-demand + splash page

An always-on static landing page that lets recruiters wake the (normally
asleep) EC2 instance with one click, then explore the live project. Saves
AWS credits by keeping the instance off until someone actually visits.

```
demo.projectbyradhe.xyz (S3+CloudFront, always on)
   └─ "▶ Wake the project" button
        └─ Lambda Function URL  →  ec2:StartInstances + tag WakeUntil=now+10m
              └─ ~2-3 min later the EC2 site is live
challenge: a cron Lambda (every 5 min) stops the instance once WakeUntil passes
```

## What Terraform creates

| Resource | Purpose |
|---|---|
| Lambda `mandigo-wake-wake` + Function URL | Starts EC2, stamps `WakeUntil` tag |
| Lambda `mandigo-wake-stop` | Stops EC2 once `WakeUntil` is in the past |
| EventBridge cron rule | Runs the stop Lambda every 5 min |
| IAM role | Scoped to Start/Stop/Tag on **only** your instance |
| S3 bucket (private) | Hosts the splash `index.html` |
| CloudFront + OAC | Serves the splash over HTTPS |
| ACM cert (us-east-1) | Only if you set a custom `splash_domain` |

## Prerequisites

- Terraform >= 1.5, AWS CLI configured with credentials for account `526955697030`.
- Your EC2 instance ID. Find it:
  ```bash
  aws ec2 describe-instances \
    --filters "Name=ip-address,Values=3.6.157.180" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text --region ap-south-1
  ```

## Deploy

```bash
cd terraform/wake

cat > terraform.tfvars <<EOF
instance_id        = "i-0xxxxxxxxxxxxxxxx"   # from the command above
keep_alive_minutes = 10
# Optional custom domain. Omit to use the *.cloudfront.net URL.
splash_domain      = "demo.projectbyradhe.xyz"
EOF

terraform init
terraform apply
```

### If you set a custom `splash_domain` (two-phase, because of GoDaddy DNS)

CloudFront needs an **issued** ACM cert, but ACM validation needs a CNAME
you add manually at GoDaddy. So custom domains take two applies:

```bash
# Phase 1 — create ONLY the cert
terraform apply -target=aws_acm_certificate.splash

# Get the validation record and add it at GoDaddy (Type=CNAME):
terraform output acm_validation_records
#   name  = "_abc123.demo.projectbyradhe.xyz."
#   value = "_xyz789.xxxxacm-validations.aws."
```

Add that CNAME at GoDaddy, wait ~5-15 min for ACM to flip the cert to
`ISSUED` (check in the ACM console, us-east-1 region), then:

```bash
# Phase 2 — create everything else (CloudFront now has a valid cert)
terraform apply

# Finally, point the subdomain at CloudFront:
terraform output subdomain_cname_instructions
#   CNAME  demo.projectbyradhe.xyz  ->  dxxxx.cloudfront.net
```

Add that second CNAME at GoDaddy. Within minutes `https://demo.projectbyradhe.xyz`
serves the splash.

> Tip: do a first pass with NO `splash_domain` (single apply, CloudFront
> default URL) to confirm the wake button works end-to-end, THEN add the
> custom domain. Far less frustrating than debugging DNS and Lambda at once.

### If you skip `splash_domain`

The splash is served at the CloudFront default domain. Get it with:
```bash
terraform output splash_url
```
Ugly URL, but zero DNS work — fine for testing before committing to the
subdomain.

## After deploy — put the splash URL on your resume

```bash
terraform output splash_url
# e.g. https://demo.projectbyradhe.xyz
```

## ArgoCD — anonymous read-only access (no login)

ArgoCD wasn't installed via this repo, so this is a manual one-time patch.
Gives anyone read-only visibility into your apps (great for showing off the
GitOps setup; read-only so they can't change anything).

```bash
# 1. Enable anonymous access
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"users.anonymous.enabled":"true"}}'

# 2. Give anonymous users the built-in read-only role
kubectl -n argocd patch configmap argocd-rbac-cm --type merge \
  -p '{"data":{"policy.default":"role:readonly"}}'

# 3. Restart argocd-server to pick up the change
kubectl -n argocd rollout restart deploy/argocd-server
```

Then ArgoCD at `https://3.6.157.180:8080` shows the app dashboard with no
login. (Security note: read-only anonymous exposes repo URLs + app names.
That's intentional for a portfolio; never grant anonymous more than
`role:readonly`.)

## Tuning / operations

- **Change the keep-alive window:** edit `keep_alive_minutes`, `terraform apply`.
- **Update the splash page:** edit `splash/index.html`, `terraform apply`
  (re-uploads to S3; CloudFront `no-cache` on index.html means it's live
  immediately).
- **Wake manually (no UI):** `curl -X POST "$(terraform output -raw wake_function_url)"`
- **Stop manually right now:** `aws ec2 stop-instances --instance-ids <id> --region ap-south-1`

## Cost

- S3: a few KB of storage — effectively free.
- CloudFront: free tier covers ~1 TB/month; a splash page is negligible.
- Lambda: free tier covers millions of invocations; you'll use dozens.
- The real savings: EC2 only runs when someone's actually looking.

## Abuse consideration

The wake Function URL is public and unauthenticated — anyone with the URL
can start the instance. The auto-stop cron caps the blast radius (instance
stops 10 min after the last wake). If this ever gets abused, options:
add a Cloudflare Turnstile / hCaptcha to the splash, or a simple shared
secret header the Lambda checks. Not worth it for a portfolio today.
