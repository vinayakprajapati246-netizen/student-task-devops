data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  name = var.project_name
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
  tags = {
    Project   = local.name
    ManagedBy = "Terraform"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name               = "${local.name}-vpc"
  cidr               = "10.20.0.0/16"
  azs                = local.azs
  public_subnets     = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnets    = ["10.20.11.0/24", "10.20.12.0/24"]
  enable_nat_gateway = false
  enable_dns_hostnames = true
  enable_dns_support   = true
  public_subnet_tags = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
  tags = local.tags
}

resource "aws_security_group" "jenkins" {
  name        = "${local.name}-jenkins-sg"
  description = "Restricted access to Jenkins and SSH"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Jenkins UI from trusted CIDR"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }
  ingress {
    description = "SSH from trusted CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

resource "aws_iam_role" "jenkins" {
  name = "${local.name}-jenkins-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "jenkins_eks_read" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy" "jenkins_eks_describe" {
  name = "${local.name}-eks-describe"
  role = aws_iam_role.jenkins.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${local.name}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true
  user_data                   = templatefile("${path.module}/jenkins-user-data.sh", { aws_region = var.aws_region })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }
  tags = merge(local.tags, { Name = "${local.name}-jenkins" })
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.1"

  cluster_name                     = "${local.name}-eks"
  cluster_version                  = var.eks_version
  cluster_endpoint_public_access   = true
  cluster_endpoint_private_access  = true
  cluster_endpoint_public_access_cidrs = [var.ssh_allowed_cidr]
  vpc_id                           = module.vpc.vpc_id
  subnet_ids                       = module.vpc.public_subnets
  control_plane_subnet_ids         = module.vpc.public_subnets
  enable_cluster_creator_admin_permissions = true

  cluster_security_group_additional_rules = {
    ingress_jenkins_https = {
      description              = "Allow Jenkins EC2 to reach the private Kubernetes API"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = aws_security_group.jenkins.id
    }
  }

  eks_managed_node_groups = {
    demo = {
      name           = "${local.name}-workers"
      instance_types = var.worker_instance_types
      min_size       = var.worker_min_size
      max_size       = var.worker_max_size
      desired_size   = var.worker_desired_size
      subnet_ids     = module.vpc.public_subnets
      capacity_type  = "ON_DEMAND"
      disk_size      = 20
    }
  }
  tags = local.tags
}

resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.jenkins.arn
  type          = "STANDARD"
}

# Demo convenience: cluster-admin for Jenkins. Narrow this to namespace-scoped RBAC in production.
resource "aws_eks_access_policy_association" "jenkins_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.jenkins.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.jenkins]
}
