variable "vpc_ids" {
  description = "Map of the VPC ID to enable flow logs on"
  type        = map(string)
}

variable "retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

locals {
  common_tags = merge({ ManagedBy = "Terraform" }, var.tags)
}
#trust policy - who is allowed to assume this role?
data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json

  tags = local.common_tags
}

#json with permissions
data "aws_iam_policy_document" "flow_logs_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    #in production we would specify to a specific log group ARNs
    resources = ["*"]

  }
}

#permission policy
resource "aws_iam_role_policy" "flow_logs" {
  name   = "vpc-flow-logs-role"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_policy.json
}

#we are creating one log group for each VPC
resource "aws_cloudwatch_log_group" "flow_logs" {
  for_each = var.vpc_ids

  name              = "/aws/vpc-flow-logs/${each.key}"
  retention_in_days = var.retention_days

  tags = merge(local.common_tags, { Name = "${each.key}-flow-log-group" })
}

#this resource captures all traffic passing through vpc. One flow log for each VPC
resource "aws_flow_log" "this" {
  for_each = var.vpc_ids

  vpc_id          = each.value
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs[each.key].arn

  tags = merge(local.common_tags, { Name = "${each.key}-flow-log" })
}

#returns the exact log groups names of each VPC. Good for debugging connectivity
output "log_group_names" {
  description = "Map of VPC name to CloudWatch log group name"
  value       = { for k, v in aws_cloudwatch_log_group.flow_logs : k => v.name }
}

