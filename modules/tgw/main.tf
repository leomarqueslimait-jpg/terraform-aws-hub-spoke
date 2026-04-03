locals {
  common_tags = merge(
    { ManagedBy = "Terraform" }, var.tags
  )
}
/* The central router itself. Connects all VPCs together. 
Has a BGP ASN for routing and DNS support to allow DNS queries
 to cross between VPCs. Without this nothing else exists. */

resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name} Transit Gateway"
  amazon_side_asn                 = var.amazon_side_asn
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"

  tags = merge(local.common_tags, {
    Name = "${var.name}-tgw"
  })
}

resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-tgw-rt-hub"
  })
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-tgw-rt-spoke"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.attachments

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${var.name}-tgw-attach-${each.key}"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["hub"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = { for k, v in var.attachments : k => v if k != "hub" }

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}


#propagation will advertise spokes CIDR blocks to hub TGW RT. AWS can learn 
#CIDR block of the attachment just by its id.

resource "aws_ec2_transit_gateway_route_table_propagation" "spokes_to_hub_rt" {
  for_each                       = { for k, v in var.attachments : k => v if k != "hub" }
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "hub_to_spoke_rt" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["hub"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

/* this next resource injects routes into the hub private table
the ids will be extract thorugh output.tf from VPC modules. 
Because it is from different modules we cannot reference directly w/
resource_type.name.id ,  we have to use output and variables . 
We also want to keep the VPCs separeted --  self-contained network,
wihtout knowing anything from other VPCs or TGWs. Each VPC module should
only know about its subnets, route tables and gateway. 
vpc module outputs the IDS and variable spoke_route_table_ids will reference it
*/
resource "aws_route" "hub_to_spoke" {
  count = length(var.spoke_cidrs)

  route_table_id         = var.hub_private_route_table_id
  destination_cidr_block = var.spoke_cidrs[count.index]
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]

}

resource "aws_route" "spokes_default_egress" {
  for_each = var.spoke_route_table_ids

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_ec2_transit_gateway_route" "spokes_default_to_hub" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["hub"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}