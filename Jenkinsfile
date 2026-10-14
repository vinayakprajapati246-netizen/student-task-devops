pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds(); buildDiscarder(logRotator(numToKeepStr: '10')) }
  environment {
    AWS_DEFAULT_REGION = 'ap-south-1' // change to the region used in Terraform
    EKS_CLUSTER_NAME = 'student-task-eks' // keep in sync with project_name + -eks
    DOCKERHUB_USER = 'YOUR_DOCKERHUB_USERNAME' // replace, or define as a Jenkins global environment variable
    K8S_NAMESPACE = 'student-task'
  }
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Test backend') {
      steps {
        dir('backend') {
          sh 'python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt && pytest -q'
        }
      }
    }
    stage('Build images') {
      steps {
        sh '''
          set -eu
          docker build -t ${DOCKERHUB_USER}/student-task-backend:${BUILD_NUMBER} -t ${DOCKERHUB_USER}/student-task-backend:latest ./backend
          docker build -t ${DOCKERHUB_USER}/student-task-frontend:${BUILD_NUMBER} -t ${DOCKERHUB_USER}/student-task-frontend:latest ./frontend
        '''
      }
    }
    stage('Push images') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
          sh '''
            set +x
            echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
            docker push ${DOCKERHUB_USER}/student-task-backend:${BUILD_NUMBER}
            docker push ${DOCKERHUB_USER}/student-task-backend:latest
            docker push ${DOCKERHUB_USER}/student-task-frontend:${BUILD_NUMBER}
            docker push ${DOCKERHUB_USER}/student-task-frontend:latest
            docker logout
          '''
        }
      }
    }
    stage('Configure EKS') {
      steps {
        sh '''
          aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name "$EKS_CLUSTER_NAME"
          kubectl get nodes
          kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
        '''
      }
    }
    stage('Deploy') {
      steps {
        sh '''
          set -eu
          sed "s|DOCKERHUB_USER|${DOCKERHUB_USER}|g" k8s/app.yaml | kubectl apply -f -
          kubectl -n "$K8S_NAMESPACE" set image deployment/backend backend=${DOCKERHUB_USER}/student-task-backend:${BUILD_NUMBER}
          kubectl -n "$K8S_NAMESPACE" set image deployment/frontend frontend=${DOCKERHUB_USER}/student-task-frontend:${BUILD_NUMBER}
          kubectl -n "$K8S_NAMESPACE" rollout status deployment/backend --timeout=180s
          kubectl -n "$K8S_NAMESPACE" rollout status deployment/frontend --timeout=180s
          kubectl -n "$K8S_NAMESPACE" get pods,svc
        '''
      }
    }
  }
  post {
    success { echo 'CI/CD completed: tested, built, pushed, deployed, and rollout verified.' }
    failure { echo 'Pipeline failed. Inspect stage logs and Kubernetes events before retrying.' }
    always { sh 'docker image prune -f || true' }
  }
}
