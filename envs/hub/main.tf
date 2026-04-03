locals {
  common_tags = {
    Project     = "hub-spoke-network"
    ManagedBy   = "Terraform"
    Environment = "hub"
  }
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

  attachments = {
    hub = {
      vpc_id     = module.hub_vpc.vpc_id
      subnet_ids = module.hub_vpc.private_subnet_ids
    }

    dev = {
      vpc_id     = data.terraform_remote_state.spoke_dev.outputs.vpc_id
      subnet_ids = data.terraform_remote_state.spoke_dev.outputs.private_subnet_ids
    }

    prod = {
      vpc_id     = data.terraform_remote_state.spoke_prod.outputs.vpc_id
      subnet_ids = data.terraform_remote_state.spoke_prod.outputs.private_subnet_ids
    }

  }
  spoke_cidrs                = ["10.1.0.0/16", "10.2.0.0/16"]
  hub_private_route_table_id = module.hub_vpc.private_route_table_id

  spoke_route_table_ids = {
    dev  = data.terraform_remote_state.spoke_dev.outputs.private_route_table_id
    prod = data.terraform_remote_state.spoke_prod.outputs.private_route_table_id
  }

  tags = local.common_tags

}

module "flow_logs" {
  source = "../../modules/flow_logs"

  vpc_ids = {
    hub  = module.hub_vpc.vpc_id
    prod = data.terraform_remote_state.spoke_prod.outputs.vpc_id
    dev  = data.terraform_remote_state.spoke_dev.outputs.vpc_id
  }

  retention_days = 7
  tags           = local.common_tags
}

module "dns" {
  source = "../../modules/dns"

  name        = "hub-spoke"
  domain_name = "internal.example.com"
  hub_vpc_id  = module.hub_vpc.vpc_id

  spoke_vpc_ids = {
    dev  = data.terraform_remote_state.spoke_dev.outputs.vpc_id
    prod = data.terraform_remote_state.spoke_prod.outputs.vpc_id


  }

  tags = local.common_tags

}

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

data "terraform_remote_state" "spoke_dev" {
  backend = "s3"
  config = {
    bucket = "hub-spoke-tf-state-new"
    key    = "spoke-dev/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "spoke_prod" {
  backend = "s3"
  config = {
    bucket = "hub-spoke-tf-state-new"
    key    = "spoke-prod/terraform.tfstate"
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

resource "aws_route53_record" "spoke_dev" {
  zone_id = module.dns.private_zone_id
  name    = "app.dev.internal.example.com"
  type    = "A"
  ttl     = 300
  records = [data.terraform_remote_state.spoke_dev.outputs.app_private_ip]
}

resource "aws_route53_record" "spoke_prod" {
  zone_id = module.dns.private_zone_id
  name    = "app.prod.internal.example.com"
  type    = "A"
  ttl     = 300
  records = [data.terraform_remote_state.spoke_prod.outputs.app_private_ip]
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

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = module.hub_vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name

  tags = merge(local.common_tags, { Name = "hub-bastion" })
}
