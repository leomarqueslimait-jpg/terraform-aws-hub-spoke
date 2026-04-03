output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDS"
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "Public route table ID - needed to add TGW routes for bastion access"
  value       = length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : null
}

output "private_route_table_id" {
  description = "ID of the private route table - TGW module will inject routes here"
  value       = length(aws_route_table.private) > 0 ? aws_route_table.private[0].id : null

}

output "nat_gateway_id" {
  description = "NAT Gateway ID (Hub only)"
  value       = var.enable_nat_gateway ? aws_nat_gateway.this[0].id : null
}

