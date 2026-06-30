variable "aws_region" {
  description = "Region where the EC2 instance + Lambdas live."
  type        = string
  default     = "ap-south-1"
}

variable "instance_id" {
  description = "The EC2 instance ID to wake/stop (e.g. i-0abc123...)."
  type        = string
}

variable "keep_alive_minutes" {
  description = "How long the instance stays up after a wake click, in minutes."
  type        = number
  default     = 10
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
