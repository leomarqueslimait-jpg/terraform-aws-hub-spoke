# trust policy - only EC2 instances can assume this role
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, { Name = "${var.name}-ssm-role" })
}

# AWS-managed policy that gives the SSM agent on the instance everything
# it needs to register with Session Manager and receive commands -
# no need to write this permission set by hand.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# an IAM role can't be attached to an EC2 instance directly - it has to be
# wrapped in an instance profile first.
resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-ssm-profile"
  role = aws_iam_role.this.name

  tags = merge(var.tags, { Name = "${var.name}-ssm-profile" })
}