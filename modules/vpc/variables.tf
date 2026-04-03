variable "name" {
  description = "Name prefix for all resources in this VPC"
  type        = string
}

variable "cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "List of Availability Zones to deploy subnets into"
  type        = list(string)
}
variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (one per AZ). Leave empty for spoke VPCs"
  type        = list(string)
  default     = []

}

variable "private_subnet_cidrs" {
  description = "The CIDRS for private subnets (one per AZ)"
  type        = list(string)

}

variable "enable_nat_gateway" {
  description = "Whether to provision a NAT Gateway (HUB only spokes route via TGW)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}


}