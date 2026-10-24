variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "student-task"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "Use 3-20 lowercase letters, numbers, or hyphens, starting with a letter."
  }
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "Your public IP with /32, e.g. 203.0.113.10/32. Never use 0.0.0.0/0."
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name in the selected region."
}

variable "eks_version" {
  type    = string
  default = "1.32"
}

variable "worker_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "worker_desired_size" {
  type    = number
  default = 1
}

variable "worker_min_size" {
  type    = number
  default = 1
}

variable "worker_max_size" {
  type    = number
  default = 2
}
variable "existing_jenkins_public_ip" {
  type        = string
  description = "Public IP of the existing Jenkins EC2 instance"
}
