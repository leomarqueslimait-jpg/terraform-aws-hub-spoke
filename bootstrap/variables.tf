variable "aws_region" {
  description = "AWS region to bootstrap into"
  type        = string
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state (must be globally unique)"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
}

variable "github_org" {
  description = "GitHub org or username that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo name"
  type        = string
}

# GitHub's documented thumbprint for the OIDC provider's root CA.
# AWS validates the full certificate chain itself; this value is required by
# the provider resource but AWS no longer actually uses it to verify trust.
variable "github_oidc_thumbprint" {
  description = "Thumbprint for token.actions.githubusercontent.com"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all bootstrap resources"
  type        = map(string)
}
