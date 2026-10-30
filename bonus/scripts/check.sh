#!/usr/bin/env bash
set -euo pipefail

cluster_name=${1:-iot}
export KUBECONFIG="${KUBECONFIG:-$(k3d kubeconfig write "$cluster_name")}"
kubectl get namespace gitlab
kubectl -n gitlab get pods
kubectl -n argocd get application playground
kubectl -n argocd get application playground -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}' |
    grep -Fx 'Synced Healthy'
kubectl -n dev rollout status deployment/wil-playground --timeout=120s
response=$(curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8888/)
grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' <<<"$response"
echo "Bonus is ready: GitLab is installed and Argo CD deploys from the local repository."
