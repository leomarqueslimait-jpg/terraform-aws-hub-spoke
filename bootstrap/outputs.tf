output "state_bucket_name" {
  description = "S3 bucket holding all environment state files"
  value       = aws_s3_bucket.tf_state.id
}

output "lock_table_name" {
  description = "DynamoDB table used for state locking"
  value       = aws_dynamodb_table.tf_lock.name
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "deploy_role_arns" {
  description = "Map of environment name to the IAM role ARN GitHub Actions assumes for it. Paste these into the corresponding repo variables (or directly into each caller workflow) as AWS_ROLE_ARN."
  value       = { for env, role in aws_iam_role.deploy : env => role.arn }
}
