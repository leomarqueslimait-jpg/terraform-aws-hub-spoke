output "hub_vpc_id" {
  description = "Hub VPC ID"
  value       = module.hub_vpc.vpc_id
}

output "hub_vpc_cidr" {
  description = "Hub VPC CIDR"
  value       = module.hub_vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Hub public subnet IDs"
  value       = module.hub_vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Hub private subnet IDs"
  value       = module.hub_vpc.private_subnet_ids
}

output "bastion_public_subnet_ip" {
  description = "Bastion public subnet IP address"
  value       = aws_instance.bastion.public_ip
}

output "tgw_id" {
  description = "Transit Gateway ID"
  value       = module.tgw.tgw_id
}

output "private_zone_id" {
  description = "Route 53 private hosted zone ID"
  value       = module.dns.private_zone_id
}

