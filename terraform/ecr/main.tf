provider "aws" {
  region = "ap-south-1"
}

# ECR for MandiGo Backend
resource "aws_ecr_repository" "mandigo_backend" {
  name = "mandigo-backend-api"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECR for MandiGo Frontend
resource "aws_ecr_repository" "mandigo_frontend" {
  name = "mandigo-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

output "backend_ecr_url" {
  value = aws_ecr_repository.mandigo_backend.repository_uri
}

output "frontend_ecr_url" {
  value = aws_ecr_repository.mandigo_frontend.repository_uri
}
