
# Get the existing Jenkins EC2 IAM role.
data "aws_iam_role" "existing_jenkins" {
  name = "student-task-jenkins-ec2-role"
}

# VPC and networking.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = "${var.project_name}-vpc"
  cidr = "10.20.0.0/16"

  azs = [
    "${var.aws_region}a",
    "${var.aws_region}b"
  ]

  public_subnets = [
    "10.20.1.0/24",
    "10.20.2.0/24"
  ]

  private_subnets = [
    "10.20.11.0/24",
    "10.20.12.0/24"
  ]

  map_public_ip_on_launch = true

  # Disable NAT Gateway to reduce AWS costs.
  enable_nat_gateway = false
  single_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# EKS cluster and worker nodes.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.1"

  cluster_name    = "${var.project_name}-eks"
  cluster_version = var.eks_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  cluster_endpoint_public_access_cidrs = [
    var.ssh_allowed_cidr,
    "${var.existing_jenkins_public_ip}/32"
  ]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  # Allow frontend NodePort 30080 from your trusted public IP.
  node_security_group_additional_rules = {
    ingress_frontend_nodeport = {
      description = "Frontend NodePort 30080 from trusted IP"
      protocol    = "tcp"
      from_port   = 30080
      to_port     = 30080
      type        = "ingress"
      cidr_blocks = [var.ssh_allowed_cidr]
    }
  }

  eks_managed_node_groups = {
    demo = {
      name           = "${var.project_name}-workers"
      instance_types = var.worker_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      subnet_ids = module.vpc.public_subnets
      disk_size  = 20

      labels = {
        Project = var.project_name
      }

      tags = {
        Project   = var.project_name
        ManagedBy = "Terraform"
      }
    }
  }

  authentication_mode = "API_AND_CONFIG_MAP"

  enable_cluster_creator_admin_permissions = true

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# Give the existing Jenkins EC2 IAM role access to EKS.
resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_iam_role.existing_jenkins.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "jenkins_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_iam_role.existing_jenkins.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.jenkins
  ]
}

variable "min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 1
}
