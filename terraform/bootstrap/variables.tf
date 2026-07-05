variable "aws_region" {
  description = "Region for the state bucket, lock table, and CI role."
  type        = string
  default     = "ap-south-1"
}

variable "github_owner" {
  description = "GitHub org/user that owns the gitops repo."
  type        = string
  default     = "theradheshyampatil"
}

variable "github_repo" {
  description = "Repo name that GitHub Actions authenticates from."
  type        = string
  default     = "mandigo-gitops"
}

variable "github_branch" {
  description = "Branch allowed to assume the CI role (least-privilege scope)."
  type        = string
  default     = "main"
}
