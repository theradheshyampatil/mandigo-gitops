data "aws_caller_identity" "current" {}

locals {
  use_custom_domain = var.splash_domain != ""
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
  # CloudWatch Logs
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
  # Describe is account-wide (the API doesn't support resource scoping well)
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  # Start/Stop/Tag scoped to JUST our one instance
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
# Splash hosting — S3 (private) behind CloudFront (OAC)
# =============================================================================

resource "aws_s3_bucket" "splash" {
  bucket        = "${var.project}-splash-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "splash" {
  bucket                  = aws_s3_bucket.splash.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Render index.html with the real wake Function URL substituted in.
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.splash.id
  key          = "index.html"
  content      = replace(
    file("${path.module}/splash/index.html"),
    "__WAKE_FUNCTION_URL__",
    aws_lambda_function_url.wake.function_url,
  )
  content_type  = "text/html"
  cache_control = "no-cache"
}

resource "aws_cloudfront_origin_access_control" "splash" {
  name                              = "${var.project}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ACM cert for the custom subdomain (only if splash_domain is set).
# Must be in us-east-1 for CloudFront.
resource "aws_acm_certificate" "splash" {
  count             = local.use_custom_domain ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = var.splash_domain
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "splash" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.project} splash page"
  price_class         = "PriceClass_200" # NA + EU + Asia (covers India)

  aliases = local.use_custom_domain ? [var.splash_domain] : []

  origin {
    domain_name              = aws_s3_bucket.splash.bucket_regional_domain_name
    origin_id                = "splash-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.splash.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "splash-s3"
    viewer_protocol_policy = "redirect-to-https"
    # AWS managed "CachingOptimized" policy
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.use_custom_domain ? [1] : []
    content {
      acm_certificate_arn      = aws_acm_certificate.splash[0].arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.use_custom_domain ? [] : [1]
    content {
      cloudfront_default_certificate = true
    }
  }
}

# Allow CloudFront (this distribution only) to read the private bucket.
data "aws_iam_policy_document" "splash_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.splash.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.splash.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "splash" {
  bucket = aws_s3_bucket.splash.id
  policy = data.aws_iam_policy_document.splash_bucket.json
}
