output "vpc_id" {
  description = "Spoke Dev VPC ID"
  value       = module.spoke_prod_vpc.vpc_id
}

output "vpc_cidr" {
  description = "Spoke Dev VPC CIDR"
  value       = module.spoke_prod_vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "Spoke Dev private subnet IDs"
  value       = module.spoke_prod_vpc.private_subnet_ids
}

output "private_route_table_id" {
  description = "Spoke Dev private route table ID"
  value       = module.spoke_prod_vpc.private_route_table_id
}

output "app_private_ip" {
  description = "Private IP of the spoke-prod app instance"
  value       = aws_instance.app.private_ip
}
