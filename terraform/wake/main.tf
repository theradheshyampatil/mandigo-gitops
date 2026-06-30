data "aws_caller_identity" "current" {}

locals {
  instance_arn = format(
    "arn:aws:ec2:%s:%s:instance/%s",
    var.aws_region,
    data.aws_caller_identity.current.account_id,
    var.instance_id,
  )
}

# =============================================================================
# IAM — shared role for both Lambdas (scoped to the single instance)
# =============================================================================

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_perms" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:CreateTags",
    ]
    resources = [local.instance_arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_perms.json
}

# =============================================================================
# Lambda packaging — zip the .mjs files (SDK v3 is in the runtime already)
# =============================================================================

data "archive_file" "wake" {
  type        = "zip"
  source_file = "${path.module}/lambda/wake.mjs"
  output_path = "${path.module}/.build/wake.zip"
}

data "archive_file" "stop" {
  type        = "zip"
  source_file = "${path.module}/lambda/stop.mjs"
  output_path = "${path.module}/.build/stop.zip"
}

resource "aws_lambda_function" "wake" {
  function_name    = "${var.project}-wake"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs20.x"
  handler          = "wake.handler"
  filename         = data.archive_file.wake.output_path
  source_code_hash = data.archive_file.wake.output_base64sha256
  timeout          = 30
  environment {
    variables = {
      INSTANCE_ID        = var.instance_id
      KEEP_ALIVE_MINUTES = tostring(var.keep_alive_minutes)
    }
  }
}

resource "aws_lambda_function" "stop" {
  function_name    = "${var.project}-stop"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs20.x"
  handler          = "stop.handler"
  filename         = data.archive_file.stop.output_path
  source_code_hash = data.archive_file.stop.output_base64sha256
  timeout          = 30
  environment {
    variables = {
      INSTANCE_ID = var.instance_id
    }
  }
}

# Public Function URL for the wake Lambda (the splash button calls this).
resource "aws_lambda_function_url" "wake" {
  function_name      = aws_lambda_function.wake.function_name
  authorization_type = "NONE"
  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
    max_age       = 86400
  }
}

# =============================================================================
# EventBridge cron — runs the stop Lambda every N minutes
# =============================================================================

resource "aws_cloudwatch_event_rule" "stop_cron" {
  name                = "${var.project}-stop-cron"
  schedule_expression = "rate(${var.stop_check_rate_minutes} minutes)"
}

resource "aws_cloudwatch_event_target" "stop_cron" {
  rule = aws_cloudwatch_event_rule.stop_cron.name
  arn  = aws_lambda_function.stop.arn
}

resource "aws_lambda_permission" "stop_cron" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_cron.arn
}

# =============================================================================
# Splash hosting note
# -----------------------------------------------------------------------------
# The splash page is NOT hosted on AWS. It lives on GitHub Pages (free,
# always-on, free HTTPS, no AWS account verification needed). See
# /docs/index.html in this repo and docs/CNAME for the custom domain.
#
# This Terraform only manages the wake/stop engine. After `terraform apply`,
# copy the wake_function_url output into docs/index.html (the WAKE_URL const).
# =============================================================================
