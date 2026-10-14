#!/usr/bin/env bash
set -euo pipefail
# Run from the project root. This deletes Kubernetes monitoring and app resources only.
helm uninstall monitoring -n monitoring 2>/dev/null || true
kubectl delete namespace student-task --ignore-not-found=true
echo "Now run: cd terraform && terraform destroy"
