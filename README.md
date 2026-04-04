# AWS Hub-and-Spoke Network Architecture

## Overview

This project implements a hub-and-spoke network architecture on AWS using Terraform reusable modules for scalability. It consists of a Hub VPC and two spoke VPCs — one for production and one for development. Spoke VPCs contain only private subnets and have no direct internet access. The Hub VPC centralizes shared services: a NAT Gateway for outbound internet access, a Transit Gateway to connect all VPCs without VPC peering, a Route 53 private hosted zone for internal DNS resolution, and a bastion host as the single secure entry point to access private instances across spoke VPCs.

---

## Architecture Diagram

```
                    ┌─────────────────────────────────────────┐
                    │              Hub VPC (10.0.0.0/16)       │
                    │                                         │
                    │  Public Subnets                         │
                    │  ┌──────────┐  ┌─────────┐             │
                    │  │ Bastion  │  │   IGW   │             │
                    │  └──────────┘  └─────────┘             │
                    │                    │                    │
                    │  Private Subnets   │                    │
                    │  ┌─────────────────▼──────────────┐    │
                    │  │         NAT Gateway             │    │
                    │  └─────────────────────────────────┘    │
                    │                                         │
                    │  Route 53 Private Zone                  │
                    │  internal.example.com                   │
                    └──────────────┬──────────────────────────┘
                                   │
                        ┌──────────▼──────────┐
                        │   Transit Gateway    │
                        └──┬──────────────┬───┘
                           │              │
           ┌───────────────▼──┐    ┌──────▼────────────┐
           │  Spoke Dev VPC   │    │  Spoke Prod VPC    │
           │  10.1.0.0/16     │    │  10.2.0.0/16       │
           │                  │    │                    │
           │  Private subnets │    │  Private subnets   │
           │  App EC2         │    │  App EC2           │
           └──────────────────┘    └────────────────────┘
```

---

## Modules

| Module | Description |
|---|---|
| `modules/vpc` | Reusable VPC factory — creates VPC, subnets, route tables, IGW, NAT Gateway |
| `modules/tgw` | Transit Gateway — attachments, route tables, associations, propagations |
| `modules/dns` | Route 53 private hosted zone and spoke VPC associations |
| `modules/flow_logs` | VPC Flow Logs to CloudWatch for all VPCs |

---

## Environments

| Environment | CIDR | Description |
|---|---|---|
| `envs/hub` | 10.0.0.0/16 | Hub VPC — owns TGW, NAT, Bastion, DNS |
| `envs/spoke-dev` | 10.1.0.0/16 | Development spoke — private subnets only |
| `envs/spoke-prod` | 10.2.0.0/16 | Production spoke — private subnets only |

---

## Skills Learned

### Terraform

I learned how to use multi-environment deployment. Each environment has a separate state file in an S3 bucket. We create a backend block where Terraform stores the state files. We can reference resources and attributes from other modules and environments using these state files. To access data from another environment you need to not only pass a backend block in each environment, but also pass a data block containing a backend attribute referencing the state file you want to access.

### AWS and Networking

Creating defense in depth with VPCs that have only private subnets, only being able to communicate with each other via Transit Gateway in the Hub VPC. The spoke VPCs are completely private and can only be accessed via the bastion in the Hub VPC. I also learned how to deploy a Transit Gateway — route tables in each VPC are not enough. You also have to create route tables, associations, and the desired propagations in the TGW itself, as well as attachments.

It was also great creating a private Route 53 hosted zone and seeing instances in different VPCs being able to communicate with each other using an A record instead of an IP address.

---

## Biggest Challenge

One of the biggest challenges was dealing with resources that Terraform does not always destroy cleanly, such as CloudWatch Log Groups and Route 53 hosted zones. This can make redeployments messy — the resource still exists in AWS but Terraform has no record of it in state, so it tries to create it again and fails. You have to either import the existing resource into Terraform state, or delete it manually through the AWS Console or CLI before reapplying.

---

## Intended Audience

This project is intended to show some of my networking skills and architecture capabilities. It is aimed at roles such as Cloud Engineer, Solutions Architect, or DevOps Engineer where understanding how to design and deploy secure, scalable network infrastructure on AWS is important. I wanted to demonstrate that I can not only deploy individual resources, but also think about how they connect to each other, why certain design decisions are made, and how to organize infrastructure as reusable code that can scale as the project grows.

---

## Design Decisions

See [modules/vpc/DECISIONS.md](modules/vpc/DECISIONS.md) for notes on key design decisions made during development, including the choice between inline routes and separate `aws_route` resources.

---

## Deployment Evidence

### CloudWatch Log Groups — VPC Flow Logs for all three VPCs
![CloudWatch Log Groups](images/Cloudwatch_loggroups.png)

### CloudWatch Log Streams — Active ENI flow log entries in Hub VPC
![CloudWatch Log Streams](images/Cloudwatch_loggroups_2.png)

### EC2 Instances — Bastion in Hub public subnet, App instances in private spoke subnets
![EC2 Instances](images/Instances.png)

### NAT Gateway — Centralized internet egress in Hub VPC public subnet
![NAT Gateway](images/NAT.png)

### Hub Private Route Table — All four routes active (local, NAT, spoke-dev via TGW, spoke-prod via TGW)
![Route Tables](images/Route_tables.png)

### Route 53 Private Hosted Zone — DNS records for all three instances
![Route 53 Hosted Zone](images/Route53_hostedzones.png)

### Security Groups — Bastion SSH restricted to single IP, spoke instances allow Hub VPC only
![Security Groups](images/Security_groupd.png)

### Transit Gateway — Hub-spoke TGW available and connected
![Transit Gateway](images/TGW.png)

### DNS Resolution — nslookup resolving all three hostnames from bastion across VPCs
![DNS Resolution](images/DNS_resolution.png)

---

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- An existing EC2 Key Pair in your AWS account
- S3 bucket and DynamoDB table for remote state (see Bootstrap section)

---

## Bootstrap Remote State

Before deploying, create the S3 bucket and DynamoDB table manually:

```bash
# Create S3 bucket
aws s3api create-bucket \
  --bucket your-tf-state-bucket \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-tf-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-tf-state-bucket \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB lock table
aws dynamodb create-table \
  --table-name tf-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Update the bucket name in all three `providers.tf` files:
```
envs/hub/providers.tf
envs/spoke-dev/providers.tf
envs/spoke-prod/providers.tf
```

---

## Deployment

Deploy in this order — spokes must exist before hub can create TGW attachments:

```bash
# 1. Deploy spoke-dev
cd envs/spoke-dev
terraform init
terraform apply

# 2. Deploy spoke-prod
cd ../spoke-prod
terraform init
terraform apply

# 3. Deploy hub last
cd ../hub
terraform init
terraform apply
```

Create a `terraform.tfvars` file in `envs/hub/` with your values:

```hcl
key_pair_name    = "your-key-pair-name"
allowed_ssh_cidr = "YOUR_IP/32"
```

---

## Testing Connectivity

Get the bastion public IP:
```bash
cd envs/hub
terraform output -raw bastion_public_subnet_ip
```

SSH to bastion:
```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<bastion_ip>
```

From bastion — test DNS resolution:
```bash
dig bastion.internal.example.com
dig app.dev.internal.example.com
dig app.prod.internal.example.com
```

Jump to a spoke instance:
```bash
ssh -A -i ~/.ssh/your-key.pem \
  -J ec2-user@<bastion_ip> \
  ec2-user@<spoke_private_ip>
```

Test internet egress via NAT:
```bash
curl https://checkip.amazonaws.com
# Should return NAT Gateway IP, not bastion IP
```

---

## Cost Estimate

| Resource | Hourly Cost |
|---|---|
| Transit Gateway | $0.05/hr |
| TGW Attachments (x3) | $0.05/hr each |
| NAT Gateway | $0.045/hr |
| EC2 t3.micro (x3) | ~$0.01/hr each |
| Route 53 Private Zone | $0.50/month |
| **Total** | **~$0.25/hr** |

Destroy resources when not in use to minimize costs.

---

## Destroy

Destroy in reverse order:

```bash
cd envs/hub && terraform destroy
cd ../spoke-dev && terraform destroy
cd ../spoke-prod && terraform destroy
```

> Note: CloudWatch Log Groups and Route 53 hosted zones may need to be
> deleted manually via the AWS Console or CLI if Terraform fails to destroy them.
