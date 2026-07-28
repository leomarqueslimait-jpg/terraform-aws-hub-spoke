output "instance_profile_name" {
  description = "Instance profile name to attach to an aws_instance so it can use SSM Session Manager"
  value       = aws_iam_instance_profile.this.name
}

output "role_arn" {
  description = "ARN of the underlying IAM role, in case another policy needs to reference it"
  value       = aws_iam_role.this.arn
}