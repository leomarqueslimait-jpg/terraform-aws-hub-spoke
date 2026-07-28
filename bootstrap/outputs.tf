output "state_bucket_name" {
  description = "S3 bucket holding all environment state files"
  value       = aws_s3_bucket.tf_state.id
}

