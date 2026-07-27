/* Bootstrap layer.
This is applied once, locally, with terraform apply run by hand from my own
machine — never by a pipeline, since it creates the very things the pipeline
and every other environment depend on: the S3 state bucket, the DynamoDB
lock table, the GitHub OIDC provider, and one IAM role per environment that
GitHub Actions assumes to run plan/apply. Nothing in here has a backend
block (see providers.tf) and nothing in envs/ or modules/ should ever be
imported into this state file.
*/

data "aws_caller_identity" "current" {}

locals {
  common_tags = var.tags

  # One entry per environment/state key. Everything below (the IAM role,
  # its backend-access policy, its trust policy) is built with a single
  # for_each over this map instead of being copy-pasted three times.
  environments = {
    hub = {
      state_key = "hub/terraform.tfstate"
    }
    spoke-dev = {
      state_key = "spoke-dev/terraform.tfstate"
    }
    spoke-prod = {
      state_key = "spoke-prod/terraform.tfstate"
    }
  }
}

# ---------------------------------------------------------------------------
# Remote state backend: S3 bucket + DynamoDB lock table
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  # Prevents `terraform destroy` on this bootstrap layer from taking every
  # other environment's state down with it.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, { Name = var.state_bucket_name })
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(local.common_tags, { Name = var.lock_table_name })
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider
# No long-lived AWS access keys stored in GitHub secrets. GitHub issues a
# short-lived OIDC token per workflow run, and each IAM role below trusts
# that token instead of a static credential.
#
# This is a `resource`, imported once via
# bootstrap/import-existing-resources.sh, not a `data` source — kept
# consistent with the S3 bucket and DynamoDB table below, which are also
# resource + import. An AWS account can only have one OIDC provider per
# issuer URL (it's account-wide, not per-project), so if you've already set
# one up for another project, import it here rather than letting apply try
# to create a duplicate.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.github_oidc_thumbprint]

  tags = merge(local.common_tags, { Name = "github-actions-oidc" })
}

# ---------------------------------------------------------------------------
# Per-environment IAM roles
# One role per environment instead of one shared role, so a compromised or
# misconfigured spoke-dev workflow can't touch hub's TGW/DNS/flow-logs
# resources or hub's state file, and vice versa.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  for_each = local.environments

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Allows this role to be assumed by: a pull_request run against this
    # repo (for plan), and a push to main in this repo (for apply, gated
    # separately by a GitHub Environment approval — see the workflows).
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:pull_request",
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each = local.environments

  name               = "gha-${each.key}-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json

  tags = merge(local.common_tags, { Name = "gha-${each.key}-deploy-role" })
}

# --- Backend access: state file + lock table -------------------------------
# Each role gets full read/write on its own state object only. Hub's
# read-only access to the two spoke state objects lives in the hub_only
# document below instead of here, since that's exactly what hub_only is
# for — anything only hub needs, kept out of the document shared by all
# three roles.
# The lock table itself is shared and not scoped per role — see the
# Design Decisions note in the README for why that's an accepted
# simplification here rather than per-item conditions.

data "aws_iam_policy_document" "backend_access" {
  for_each = local.environments

  statement {
    sid    = "OwnStateReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.tf_state.arn}/${each.value.state_key}"]
  }

  statement {
    sid    = "ListStateBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.tf_state.arn]
  }

  statement {
    sid    = "StateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }
}

resource "aws_iam_role_policy" "backend_access" {
  for_each = local.environments

  name   = "backend-access"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.backend_access[each.key].json
}

# --- Infrastructure access: networking + compute, all three environments ---
# Every environment's vpc module creates the same category of resources
# (VPC, subnets, route tables, IGW/NAT, security groups, EC2 instances), so
# this one policy is shared across hub, spoke-dev, and spoke-prod.
# Resource scoping is left at "*" for ec2 actions — AWS doesn't expose
# resource-level ARNs for most VPC networking calls, so tightening this
# further means switching to tag-based conditions instead, which is a
# reasonable next step but out of scope for this portfolio project.

data "aws_iam_policy_document" "network_common" {
  statement {
    sid    = "NetworkingAndCompute"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "network_common" {
  for_each = local.environments

  name   = "network-common"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.network_common.json
}

# --- Hub-only access: TGW, Route 53, CloudWatch Logs, flow-logs IAM role, ---
# --- and read-only access to the two spoke state objects -------------------
# Only envs/hub calls modules/tgw, modules/dns, and modules/flow_logs, so
# only the hub role gets those permissions. Spoke-dev and spoke-prod never
# touch a Transit Gateway, a hosted zone, or a log group directly. Only hub
# reads the spoke state files too, since envs/hub/main.tf is the only place
# using terraform_remote_state to reach them (for the TGW attachments and
# DNS associations) — spokes never read anyone else's state.

data "aws_iam_policy_document" "hub_only" {
  statement {
    sid    = "ReadSpokeStateForRemoteState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.tf_state.arn}/spoke-dev/terraform.tfstate",
      "${aws_s3_bucket.tf_state.arn}/spoke-prod/terraform.tfstate",
    ]
  }

  statement {
    sid    = "TransitGateway"
    effect = "Allow"
    actions = [
      "ec2:CreateTransitGateway",
      "ec2:DeleteTransitGateway",
      "ec2:ModifyTransitGateway",
      "ec2:CreateTransitGatewayVpcAttachment",
      "ec2:DeleteTransitGatewayVpcAttachment",
      "ec2:ModifyTransitGatewayVpcAttachment",
      "ec2:CreateTransitGatewayRouteTable",
      "ec2:DeleteTransitGatewayRouteTable",
      "ec2:AssociateTransitGatewayRouteTable",
      "ec2:DisassociateTransitGatewayRouteTable",
      "ec2:EnableTransitGatewayRouteTablePropagation",
      "ec2:DisableTransitGatewayRouteTablePropagation",
      "ec2:CreateTransitGatewayRoute",
      "ec2:DeleteTransitGatewayRoute",
      "ec2:ReplaceTransitGatewayRoute",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Route53PrivateZone"
    effect = "Allow"
    actions = [
      "route53:CreateHostedZone",
      "route53:DeleteHostedZone",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:AssociateVPCWithHostedZone",
      "route53:DisassociateVPCFromHostedZone",
      "route53:ChangeTagsForResource",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "FlowLogsCloudWatch"
    effect = "Allow"
    actions = [
      "ec2:CreateFlowLogs",
      "ec2:DeleteFlowLogs",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:TagResource",
    ]
    resources = ["*"]
  }

  # Scoped tightly to the one role the flow_logs module creates
  # (modules/flow_logs/main.tf -> aws_iam_role.flow_logs, name
  # "vpc-flow-logs-role"), not to IAM roles in general.
  statement {
    sid    = "FlowLogsDeliveryRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/vpc-flow-logs-role"
    ]
  }
}

resource "aws_iam_role_policy" "hub_only" {
  name   = "hub-only"
  role   = aws_iam_role.deploy["hub"].id
  policy = data.aws_iam_policy_document.hub_only.json
}
