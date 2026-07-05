# Remote state for the ECR module. Uses PARTIAL configuration: the bucket /
# key / region / lock table are supplied at `terraform init` time (by CI and
# by the local runbook) so this file carries no environment-specific values.
#
#   terraform init \
#     -backend-config="bucket=mandigo-tfstate-<ACCOUNT_ID>" \
#     -backend-config="key=ecr/terraform.tfstate" \
#     -backend-config="region=ap-south-1" \
#     -backend-config="dynamodb_table=mandigo-tf-lock" \
#     -backend-config="encrypt=true"
#
# See terraform/bootstrap/README.md for the one-time setup + how to import the
# already-existing ECR repositories into this fresh remote state.
terraform {
  backend "s3" {}
}
