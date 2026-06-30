terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Primary region — where the EC2 instance and Lambdas live.
provider "aws" {
  region = var.aws_region
}

# CloudFront ACM certificates MUST be created in us-east-1, regardless of
# where the rest of the stack lives. This aliased provider is used only for
# the splash certificate.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
