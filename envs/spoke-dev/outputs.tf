output "vpc_id" {
  description = "Spoke Dev VPC ID"
  value       = module.spoke_dev_vpc.vpc_id
}

output "vpc_cidr" {
  description = "Spoke Dev VPC CIDR"
  value       = module.spoke_dev_vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "Spoke Dev private subnet IDs"
  value       = module.spoke_dev_vpc.private_subnet_ids
}

output "private_route_table_id" {
  description = "Spoke Dev private route table ID"
  value       = module.spoke_dev_vpc.private_route_table_id
}

output "app_private_ip" {
  description = "Private IP of the spoke-dev app instance"
  value       = aws_instance.app.private_ip
}

output "app_instance_id" {
  description = "Spoke-dev app instance ID - use this as the --target for aws ssm start-session"
  value       = aws_instance.app.id
}