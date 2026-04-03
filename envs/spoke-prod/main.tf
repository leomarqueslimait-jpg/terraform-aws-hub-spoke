locals {
  common_tags = {
    Project     = "hub-spoke-network"
    ManagedBy   = "Terraform"
    Environment = "spoke-prod"
  }
}

module "spoke_prod_vpc" {
  source     = "../../modules/vpc"
  name       = "spoke-prod"
  cidr_block = "10.2.0.0/16"

  azs = ["${var.aws_region}a", "${var.aws_region}b"]

  enable_nat_gateway   = false
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]
  tags                 = local.common_tags
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "app" {
  name        = "spoke-prod-app-sg"
  description = "Allow traffic from Hub VPC only"
  vpc_id      = module.spoke_prod_vpc.vpc_id

  ingress {
    description = "All trafic from Hub VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    /*I was thinking about passing cidr_blocks = ["${aws_instance.bastion.private_ip}/32"]
so I could use the /32 bastion IP, which would be more control over traffic, but this lives
 outside the module and we can't reference it. Then, I thought to passing
data.terraform_remote_state.hub.outputs.bastion_sg_id, however, both methods creates
circular dependency. Bastion lives in the Hub module, so we would need that running 
to extract the bastion ip, but Hub needs spokes vpc running first to extract spoke VPC IDs.
so I decided to go with bastion /24 subnet 
*/
    cidr_blocks = ["10.0.0.0/24"]
  }

  ingress {
    description = "ICMP from Hub for testing"
    to_port     = "-1"
    from_port   = "-1"
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "spoke-prod-app-sg" })
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = module.spoke_prod_vpc.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = false
  key_name                    = "hub-spoke-bastion"
  tags                        = merge(local.common_tags, { Name = "spoke-prod-app" })

}