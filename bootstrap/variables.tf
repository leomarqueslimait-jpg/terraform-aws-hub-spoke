variable "aws_region" {
  description = "AWS region to bootstrap into"
  type        = string
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state (must be globally unique)"
  type        = string
}


variable "tags" {
  description = "Common tags applied to all bootstrap resources"
  type        = map(string)
}

