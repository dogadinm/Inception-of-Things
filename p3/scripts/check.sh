#!/usr/bin/env bash
set -euo pipefail

cluster_name=${1:-iot}
export KUBECONFIG="${KUBECONFIG:-$(k3d kubeconfig write "$cluster_name")}"

kubectl get namespaces argocd dev
kubectl -n argocd get pods
kubectl -n dev rollout status deployment/wil-playground --timeout=60s
kubectl -n dev get deployment,pod,service
kubectl -n argocd get application playground
kubectl -n argocd get application playground -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}' |
    grep -Fx 'Synced Healthy'

response=$(curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8888/)
grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' <<<"$response"
echo "Part 3 is ready: Argo CD is Synced/Healthy and the application answers on port 8888."
