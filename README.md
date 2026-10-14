# Student Task Manager — AWS EKS DevOps Project

A learning project demonstrating GitHub → Jenkins → tests → Docker Hub → AWS EKS/Kubernetes → Prometheus/Grafana. Terraform provisions a VPC, EKS cluster, managed worker nodes, and a Jenkins EC2 instance.

> **Cost warning:** EKS has a per-cluster control-plane charge, in addition to EC2 workers, Jenkins EC2, EBS, NAT/public IPv4/load balancer and data-transfer costs. This is not guaranteed free. Create it for a short demo, monitor Billing, and run `terraform destroy` when finished. Terraform destroy removes the environment; back up anything you need first.

## Contents
- `frontend/`: static HTML/CSS/JS web UI served by Nginx
- `backend/`: Flask REST API with SQLite demo persistence
- `terraform/`: AWS infrastructure (VPC, EKS managed node group, Jenkins EC2 + IAM)
- `k8s/`: Kubernetes Deployments, Services, and probes
- `monitoring/`: Prometheus/Grafana Helm values and scrape configuration
- `Jenkinsfile`: CI/CD pipeline
- `scripts/`: helper commands

## Prerequisites
1. An AWS account with billing alerts configured; AWS CLI credentials locally for Terraform.
2. Terraform >= 1.6, AWS CLI v2, `kubectl`, `helm`, Docker, Git.
3. A Docker Hub account. Create a public repository or use a private repository with Jenkins credentials.
4. Choose a unique `project_name` (lowercase letters, numbers, hyphens).

## 1. Build and test locally
```bash
cd backend
python -m venv .venv
# Windows PowerShell: .venv\\Scripts\\Activate.ps1
# Linux/macOS: source .venv/bin/activate
pip install -r requirements.txt
pytest -q
cd ..
docker compose up --build
```
Open http://localhost:8080. API health: http://localhost:5000/health. Stop with `docker compose down`.

## 2. Provision AWS infrastructure
Run from `terraform/`:
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit project_name, region, key_name and your SSH CIDR. Do not commit terraform.tfvars.
aws configure
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```
The configuration creates a Jenkins EC2 instance and EKS managed node group. The Jenkins instance is assigned an IAM role and EKS access entry. SSH is limited to `ssh_allowed_cidr`; use your public IP with `/32`, not `0.0.0.0/0`.

Get outputs:
```bash
terraform output
terraform output -raw jenkins_public_ip
terraform output -raw ecr_not_used_dockerhub_note
```
Jenkins is at `http://JENKINS_PUBLIC_IP:8080`. Port 8080 is open only to `ssh_allowed_cidr` by default. For access from another network, update the CIDR and apply again. Never expose Jenkins to the whole internet.

Retrieve the initial password on the instance:
```bash
ssh -i PATH_TO_KEY.pem ubuntu@JENKINS_PUBLIC_IP
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```
The EC2 user-data installs Jenkins, Docker, kubectl, Helm, AWS CLI and Terraform. First boot can take several minutes. If installation failed, inspect `/var/log/cloud-init-output.log`.

## 3. Configure Docker Hub and Jenkins
1. Create Docker Hub repositories named `student-task-frontend` and `student-task-backend` (public is easiest for a demo).
2. In Jenkins → Manage Jenkins → Credentials, add a **Username with password** credential with ID `dockerhub-creds`. Use a Docker Hub access token as the password.
3. Install/enable Pipeline, Git, Credentials Binding and SSH Agent plugins if not present.
4. Create a Pipeline job connected to your GitHub repository; choose “Pipeline script from SCM”, Git, branch `main`, script path `Jenkinsfile`.
5. Set the job parameters/environment values described in the `Jenkinsfile` comments: `DOCKERHUB_USER` should be configured as a Jenkins global environment variable or adjusted in the file. The `dockerhub-creds` credential supplies login.
6. Ensure Jenkins EC2 role has EKS access. Terraform creates an EKS access entry for the Jenkins instance role. The pipeline runs `aws eks update-kubeconfig`.
7. Push this repository to GitHub, then run the Jenkins job.

Example GitHub setup:
```bash
git init
git add .
git commit -m "Initial student task DevOps project"
git branch -M main
git remote add origin https://github.com/YOUR_USER/student-task-devops.git
git push -u origin main
```

## 4. App behavior and persistence note
- `GET /api/tasks`, `POST /api/tasks`, `PATCH /api/tasks/<id>`, and `DELETE /api/tasks/<id>` are available.
- SQLite is used to keep the demo easy to run. The included Kubernetes backend uses `emptyDir`, so tasks reset when the pod is replaced. **Do not use this storage design for production.** For durable production data, use Amazon RDS or another managed database and credentials via Secrets Manager.

## 5. Monitoring with Prometheus and Grafana
After the app deploys, connect to the cluster from a terminal with AWS credentials and run:
```bash
aws eks update-kubeconfig --region YOUR_REGION --name YOUR_CLUSTER_NAME
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace -f monitoring/values.yaml
kubectl apply -f monitoring/servicemonitor.yaml
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```
Open http://localhost:3000. Default chart username is `admin`; get the generated password:
```bash
kubectl -n monitoring get secret monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
```
Use the same port-forward pattern for Prometheus if required:
```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```
Monitoring adds memory/CPU demand and may increase worker-node costs. Only install it during the demo if the node group has sufficient resources. The Flask app exposes `/metrics` using `prometheus-flask-exporter`; ServiceMonitor scrapes that endpoint.

## 6. Useful verification commands
```bash
kubectl get nodes
kubectl get pods -A
kubectl -n student-task get deploy,svc
kubectl -n student-task rollout status deployment/backend
kubectl -n student-task rollout status deployment/frontend
kubectl -n student-task logs deployment/backend
```
Get the frontend URL:
```bash
kubectl -n student-task get svc frontend
```
The frontend Service is `LoadBalancer`, which can incur additional AWS load balancer costs. For a lower-cost demo, change it to `NodePort` and use port-forwarding instead:
```bash
kubectl -n student-task port-forward svc/frontend 8080:80
```
Then open http://localhost:8080. The provided default is `LoadBalancer` for a more cloud-realistic demonstration.

## 7. Clean up — IMPORTANT
First remove Helm monitoring and application resources if desired:
```bash
helm uninstall monitoring -n monitoring || true
kubectl delete namespace student-task --ignore-not-found
```
Then destroy Terraform resources from the same `terraform/` folder:
```bash
terraform destroy
```
Check AWS Billing/Cost Explorer for leftover resources, especially load balancers, EBS volumes, public IPv4 addresses, snapshots and NAT gateways. This Terraform setup intentionally avoids a NAT Gateway to reduce costs; private worker nodes use public subnets for this training environment. For production, use private nodes and proper egress controls.

## Security / production caveats
- Demo configuration grants the Jenkins role EKS cluster-admin access so the pipeline can deploy. Reduce permissions for production.
- Restrict Jenkins access CIDR and use TLS/reverse proxy for real use.
- Never commit credentials, `.tfstate`, `.tfvars`, Docker Hub tokens, or kubeconfig.
- A single small worker node is not highly available and may not fit all monitoring workloads. Increase node size/count only for the demo and expect higher costs.
