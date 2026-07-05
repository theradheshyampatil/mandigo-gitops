terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # This module bootstraps the remote-state backend itself, so it cannot use
  # one (chicken-and-egg). Its state stays local and is gitignored. You apply
  # it ONCE from your laptop; after that everything else uses S3.
}

provider "aws" {
  region = var.aws_region
}
