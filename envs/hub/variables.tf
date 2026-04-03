variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "allowed_ssh_cidr" {
  description = "Your IP in CIDR notation for bastion SSH"
  type        = string
}

variable "key_pair_name" {
  description = "Name of an existing EC2 Pair for bastion SSH"
  type        = string
}

variable "spoke_cidrs" {
  description = "List of spoke CIDR blocks"
  type        = list(string)
  default     = ["10.1.0.0/16", "10.2.0.0/16"]
}