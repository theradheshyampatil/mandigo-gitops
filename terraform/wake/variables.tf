variable "aws_region" {
  description = "Region where the EC2 instance + Lambdas live."
  type        = string
  default     = "ap-south-1"
}

variable "instance_id" {
  description = <<-EOT
    The EC2 instance ID to wake/stop (e.g. i-0abc123...).
    Find it with: aws ec2 describe-instances \
      --filters "Name=ip-address,Values=3.6.157.180" \
      --query 'Reservations[0].Instances[0].InstanceId' --output text
  EOT
  type        = string
}

variable "keep_alive_minutes" {
  description = "How long the instance stays up after a wake click, in minutes."
  type        = number
  default     = 10
}

variable "splash_domain" {
  description = <<-EOT
    The subdomain to serve the always-on splash page on
    (e.g. demo.projectbyradhe.xyz). Leave empty to use the default
    CloudFront *.cloudfront.net domain instead (no ACM cert / DNS needed).
  EOT
  type    = string
  default = ""
}

variable "project" {
  description = "Name prefix for all created resources."
  type        = string
  default     = "mandigo-wake"
}

variable "stop_check_rate_minutes" {
  description = "How often the auto-stop cron runs."
  type        = number
  default     = 5
}
