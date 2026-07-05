# =============================================================================
# Bootstrap — the tiny, one-time foundation the rest of the IaC stands on:
#
#   1. S3 bucket        -> remote Terraform state (versioned + encrypted)
#   2. DynamoDB table   -> state locking (prevents concurrent applies)
#   3. GitHub OIDC       -> GitHub Actions assumes a role with NO static keys
#   4. IAM role/policy  -> least-privilege perms for the ECR terraform in CI
#
# Cost: effectively $0 — a near-empty S3 bucket + a PAY_PER_REQUEST DynamoDB
# table + IAM (free). Well within the $200 credit budget.
#
# Run ONCE, locally:  see README.md in this directory.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "mandigo-tfstate-${local.account_id}" # globally-unique, deterministic
  lock_table   = "mandigo-tf-lock"
}

# -----------------------------------------------------------------------------
# 1. Remote state bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire noncurrent state versions after 90 days so history doesn't grow forever.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# -----------------------------------------------------------------------------
# 2. State lock table
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "tf_lock" {
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST" # no idle cost
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# -----------------------------------------------------------------------------
# 3. GitHub OIDC provider — lets Actions exchange its signed token for AWS creds
# -----------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's OIDC root CA thumbprints. AWS now verifies against its own trust
  # store, but the provider still wants these populated.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fce",
  ]
}

# -----------------------------------------------------------------------------
# 4. CI role — assumable ONLY by this repo's `main` branch via OIDC
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ci_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "mandigo-gitops-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_assume.json
}

data "aws_iam_policy_document" "ci_perms" {
  # Remote state access
  statement {
    sid     = "TfStateBucket"
    actions = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }
  statement {
    sid       = "TfStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
  statement {
    sid       = "TfLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }

  # ECR management — CreateRepository/Describe can't be scoped to a not-yet-
  # existing repo, so those run against "*"; everything else is scoped to the
  # two MandiGo repos.
  statement {
    sid = "EcrCreateAndList"
    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
      "ecr:TagResource",
      "ecr:UntagResource",
    ]
    resources = ["*"]
  }
  statement {
    sid = "EcrManageRepos"
    actions = [
      "ecr:DeleteRepository",
      "ecr:PutImageScanningConfiguration",
      "ecr:SetRepositoryPolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/mandigo-backend-api",
      "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/mandigo-frontend",
    ]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "mandigo-gitops-ci-policy"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_perms.json
}
