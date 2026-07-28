locals {
  common_tags = merge(
  { ManagedBy = "Terraform" }, var.tags)
}
 
resource "aws_route53_zone" "private" {
  name = var.domain_name
 
  vpc {
    vpc_id = var.hub_vpc_id
  }
}
 
resource "aws_route53_zone_association" "spokes" {
  for_each = var.spoke_vpc_ids
 
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = each.value
 
}