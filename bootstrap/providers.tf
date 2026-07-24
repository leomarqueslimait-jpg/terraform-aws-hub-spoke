terraform {
  required_version = "~> 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block here on purpose. Bootstrap creates the S3 bucket and
  # DynamoDB table that every other environment's backend depends on, so it
  # can't depend on them itself. This is applied once, locally, with local
  # state, before the pipeline or any other environment exists.
}

provider "aws" {
  region = var.aws_region
}
