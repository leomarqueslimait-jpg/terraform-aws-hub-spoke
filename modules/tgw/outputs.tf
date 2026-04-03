output "tgw_id" {
  description = "Transit Gateway ID - consumed by spoke envs via remote state"
  value       = aws_ec2_transit_gateway.this.id
}

#needed in case project is exteded with Resource Access Manager

output "tgw_arn" {
  description = "Transit Gateway ARN"
  value       = aws_ec2_transit_gateway.this.arn
}

output "hub_route_table_id" {
  description = "TGW route table ID for Hub attachment"
  value       = aws_ec2_transit_gateway_route_table.hub.id
}

#Exposes both TGW route table IDs. Useful if you later add a Network Firewall
#module or want to add additional static routes from outside this module without modifying 
#it directly.

output "spokes_route_table_id" {
  description = "TGW route table ID for Spokes attachment"
  value       = aws_ec2_transit_gateway_route_table.spoke.id
}

/* aws_ec2_transit_gateway_vpc_attachment.this was created using for_each expression
the for loop goes through each entry. v = the id attribute of each item. It will create
a new map key = id
Useful for debugging and for any future modules that need to reference specific attahcment IDs
*/
output "attachments_ids" {
  description = "Map of attachment name to TGW attachment ID"
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}