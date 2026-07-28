/* Bootstrap layer.
This is applied once, locally, with terraform apply run by hand from my own
machine. It creates the S3 state bucket and the DynamoDB lock table that
every other environment depends on. Nothing in here has a backend block
(see providers.tf) and nothing in envs/ or modules/ should ever be imported
into this state file.
*/

locals {
  common_tags = var.tags
}

# ---------------------------------------------------------------------------
# Remote state backend: S3 bucket + DynamoDB lock table
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  # Prevents `terraform destroy` on this bootstrap layer from taking every
  # other environment's state down with it.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, { Name = var.state_bucket_name })
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

