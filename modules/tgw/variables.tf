variable "name" {
  description = "Name prefix for TGW resources"
  type        = string
}

#TGW uses BGP internally to exchange routes. ASN 64512 is in the private ASN range
variable "amazon_side_asn" {
  description = "BGP ASN for the Transit gateway"
  type        = number
  default     = 64512
}

variable "attachments" {
  description = "Map of VPC attachments to create. Key = logical name (e.g. hub, dev, prod)"
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
  }))
}

variable "spoke_cidrs" {
  description = "List of spoke CIDR blocks - used to build Hub to Spoke routes"
  type        = list(string)
  default     = []

}

variable "hub_private_route_table_id" {
  description = "Route table ID in the Hub VPC to inject spoke routes into"
  type        = string
}

variable "spoke_route_table_ids" {
  description = "Map of spoke name to private route table ID for injecting default route"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Addional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

