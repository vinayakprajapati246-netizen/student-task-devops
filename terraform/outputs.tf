output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "aws_region" {
  value = var.aws_region
}

output "ecr_not_used_dockerhub_note" {
  value = "Docker Hub is used for image storage; no ECR repository is created."
}
