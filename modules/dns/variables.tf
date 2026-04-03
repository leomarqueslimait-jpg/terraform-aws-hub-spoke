variable "name" {
  description = "Name prefix for DNS resolver resources"
  type        = string
}

variable "hub_vpc_id" {
  description = "Hub VPC ID - where the inbound resolver endpoint lives"
  type        = string
}

variable "spoke_vpc_ids" {
  description = "Map of spoke name to VPC ID for zone and rule association"
  type        = map(string)
  default     = {}

}

variable "domain_name" {
  description = "Private hosted zone domain name"
  type        = string
  default     = "internal.example.com"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}