# Bootstrap — remote state + keyless CI (one-time)

This module replaces two liabilities in the old setup:

1. **No remote state.** The ECR workflow ran `terraform apply` on an ephemeral
   GitHub runner with local state, so state was thrown away every run. The
   first push created the repos; every later push started from empty state,
   tried to *re-create* repos that already exist, and failed with
   `RepositoryAlreadyExistsException`. Fixed by an S3 backend + DynamoDB lock.

2. **Long-lived AWS keys in GitHub secrets.** Replaced by GitHub OIDC: the CI
   job assumes an IAM role scoped to `main` of this repo — no static keys.

Everything created here costs ~$0 (near-empty S3 bucket + PAY_PER_REQUEST
DynamoDB + IAM).

## Run it once (from your laptop)

You need AWS admin creds locally for this single bootstrap (afterwards CI is
keyless). The instance/cluster is unaffected — this only touches S3, DynamoDB,
and IAM.

```bash
cd terraform/bootstrap
terraform init                 # local state (gitignored) — that's intentional
terraform apply                # review, then approve
terraform output               # note the three outputs
```

Outputs:
- `state_bucket`  → e.g. `mandigo-tfstate-526955697030`
- `lock_table`    → `mandigo-tf-lock`
- `ci_role_arn`   → `arn:aws:iam::526955697030:role/mandigo-gitops-ci`

## Wire the ECR module to remote state

The ECR repos already exist, so import them into the fresh remote state
(otherwise the first apply tries to create them again):

```bash
cd ../ecr
terraform init \
  -backend-config="bucket=$(terraform -chdir=../bootstrap output -raw state_bucket)" \
  -backend-config="key=ecr/terraform.tfstate" \
  -backend-config="region=ap-south-1" \
  -backend-config="dynamodb_table=mandigo-tf-lock" \
  -backend-config="encrypt=true"

terraform import aws_ecr_repository.mandigo_backend  mandigo-backend-api
terraform import aws_ecr_repository.mandigo_frontend mandigo-frontend

terraform plan   # should now show "No changes"
```

## Point CI at OIDC

In the GitHub repo (Settings → Secrets and variables → Actions), add:

| Secret name        | Value                          |
|--------------------|--------------------------------|
| `AWS_ROLE_ARN`     | the `ci_role_arn` output       |
| `AWS_STATE_BUCKET` | the `state_bucket` output      |

Then delete the now-unused `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
secrets. The workflow (`.github/workflows/terraform-apply.yml`) already uses
`role-to-assume` + these two values.

## Verify

Push a trivial change under `terraform/ecr/` (e.g. a comment). The workflow
should: auth via OIDC → init against S3 → `fmt`/`validate`/`plan` → apply with
**no** changes. Green run = done.
