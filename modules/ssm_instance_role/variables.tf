variable "name" {
  description = "Name prefix for the IAM role and instance profile (e.g. \"hub-bastion\", \"spoke-dev-app\")"
  type        = string
}

variable "tags" {
  description = "Tags applied to the IAM role and instance profile"
  type        = map(string)
  default     = {}
}