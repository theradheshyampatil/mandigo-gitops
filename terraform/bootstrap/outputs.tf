output "state_bucket" {
  description = "S3 bucket holding remote Terraform state. Use in `terraform init -backend-config`."
  value       = aws_s3_bucket.tfstate.id
}

output "lock_table" {
  description = "DynamoDB table for state locking."
  value       = aws_dynamodb_table.tf_lock.name
}

output "ci_role_arn" {
  description = "ARN of the GitHub Actions OIDC role. Set this as the AWS_ROLE_ARN repo secret / variable."
  value       = aws_iam_role.ci.arn
}
