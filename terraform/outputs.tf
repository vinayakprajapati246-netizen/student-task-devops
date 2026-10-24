
output "jenkins_public_ip" {
  description = "Public IP of the existing Jenkins EC2 instance"
  value       = var.existing_jenkins_public_ip
}

output "jenkins_url" {
  description = "Jenkins web interface URL"
  value       = "http://${var.existing_jenkins_public_ip}:8080"
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS Kubernetes API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_region" {
  description = "AWS region of the EKS cluster"
  value       = var.aws_region
}
