locals {
  common_tags = {
    Project     = "hub-spoke-network"
    ManagedBy   = "Terraform"
    Environment = "hub"
  }

  # Single source of truth for "which spokes exist." Adding a third spoke
  # means adding one string here — the remote state lookup, the TGW
  # attachment, the flow logs VPC list, the DNS zone association, and the
  # app.<env>.internal.example.com record all pick it up automatically.
  spoke_envs = toset(["dev", "prod"])
}

module "hub_vpc" {
  source     = "../../modules/vpc"
  name       = "hub"
  cidr_block = "10.0.0.0/16"
  azs        = ["${var.aws_region}a", "${var.aws_region}b"]

  enable_nat_gateway   = true
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  tags                 = local.common_tags

}

module "tgw" {
  source = "../../modules/tgw"
  name   = "hub-spoke"


  attachments = merge(
    {
      hub = {
        vpc_id     = module.hub_vpc.vpc_id
        subnet_ids = module.hub_vpc.private_subnet_ids
      }
    },
    {
      for env, state in data.terraform_remote_state.spokes : env => {
        vpc_id     = state.outputs.vpc_id
        subnet_ids = state.outputs.private_subnet_ids
      }
    }
  )

  spoke_cidrs                = [for env, state in data.data.terraform_remote_state.spokes : state.output.vpc_cidr]
  hub_private_route_table_id = module.hub_vpc.private_route_table_id

  spoke_route_table_ids = {
    for env, state in data.terraform_remote_state.spokes : env => state.outputs.private_route_table_id
  }

  tags = local.common_tags

}

module "flow_logs" {
  source = "../../modules/flow_logs"

  vpc_ids = merge(
    { hub = module.hub_vpc.vpc_id },
    { for env, state in data.terraform_remote_state.spokes : env => state.outputs.vpc_id }
  )

  retention_days = 7
  tags           = local.common_tags
}

module "dns" {
  source = "../../modules/dns"

  name        = "hub-spoke"
  domain_name = "internal.example.com"
  hub_vpc_id  = module.hub_vpc.vpc_id

  spoke_vpc_ids = {
    for env, state in data.terraform_remote_state.spokes : env => state.outputs.vpc_id
  }

  tags = local.common_tags

}

#So bastian can access spoke vpcs
resource "aws_route" "public_to_spokes" {
  count = length(var.spoke_cidrs)

  route_table_id         = module.hub_vpc.public_route_table_id
  destination_cidr_block = var.spoke_cidrs[count.index]
  transit_gateway_id     = module.tgw.tgw_id
}

resource "aws_route" "hub_private_to_nat" {
  route_table_id         = module.hub_vpc.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = module.hub_vpc.nat_gateway_id
}

data "terraform_remote_state" "spokes" {
  for_each = local.spoke_envs

  backend = "s3"
  config = {
    bucket = "hub-spoke-tf-state-new"
    key    = "spoke-${each.key}/terraform.tfstate"
    region = "us-east-1"
  }
}


resource "aws_route53_record" "bastion" {
  zone_id = module.dns.private_zone_id
  name    = "bastion.internal.example.com"
  type    = "A"
  ttl     = 300
  records = [aws_instance.bastion.private_ip]
}

resource "aws_route53_record" "spokes" {
  for_each = data.terraform_remote_state.spokes

  zone_id = module.dns.private_zone_id
  name    = "app.${each.key}.internal.example.com"
  type    = "A"
  ttl     = 300
  records = [each.value.outputs.app_private_ip]
}

# aws_route53_record.spoke_dev and aws_route53_record.spoke_prod used to be
# two hand-written resources. They became aws_route53_record.spokes["dev"]
# and ["prod"] above — same records, new addresses. Without these `moved`
# blocks, Terraform would see the old addresses missing from config and the
# new ones as unrelated, and plan to destroy + recreate both DNS records
# instead of recognizing they're the same resources that just moved.
moved {
  from = aws_route53_record.spoke_dev
  to   = aws_route53_record.spokes["dev"]
}

moved {
  from = aws_route53_record.spoke_prod
  to   = aws_route53_record.spokes["prod"]
}

resource "aws_security_group" "bastion" {
  name        = "hub-bastion-ssh"
  description = "Allow SSH inboud from my IP only, all outbound"
  vpc_id      = module.hub_vpc.vpc_id

  ingress {
    description = "Allow SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "hub-bastion-sg" })
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

module "bastion_ssm" {
  source = "../../modules/ssm_instance_role"
  name   = "hub-bastion"
  tags   = local.common_tags
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = module.hub_vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  iam_instance_profile        = module.bastion_ssm.instance_profile_name

  tags = merge(local.common_tags, { Name = "hub-bastion" })
}