#tags that will be applied for all the resources. I use variable name to distinguish different environments
locals {
  common_tags = merge(
    {
      ManagedBy   = "Terraform"
      Environment = var.name
    },
    var.tags
  )
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags,
    { Name = "${var.name}-vpc" }
  )
}

resource "aws_internet_gateway" "this" {
  count  = length(var.public_subnet_cidrs) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags,
    { Name = "${var.name}-igw" }
  )
}

#public subnets will be created depending on the numbers of public subnets cidrs entered.
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-${var.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-${var.azs[count.index]}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags,
  { Name = "${var.name}-nat-eip" })

}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags = merge(local.common_tags,
  { Name = "${var.name}-nat" })

  depends_on = [aws_internet_gateway.this]

}

# ✅ No inline routes
resource "aws_route_table" "public" {
  count  = length(var.public_subnet_cidrs) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${var.name}-public-rt" })
}

# IGW default route as separate resource
resource "aws_route" "public_internet" {
  count = length(var.public_subnet_cidrs) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  route_table_id = aws_route_table.public[0].id
  subnet_id      = aws_subnet.public[count.index].id


}

#routes will be injected by TGW module
#one route table per az because all vpc traffic exit via TGW to the hub NAT Gateway
#If we had one NATGW per AZ (HA design), we would refactor it to one route table
#per subnet, so each AZ routes to its local nat and avoid cross-AZ cost
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

