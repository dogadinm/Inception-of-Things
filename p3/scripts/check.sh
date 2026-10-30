#!/usr/bin/env bash
set -euo pipefail

cluster_name=${1:-iot}
expected_version=${2:-}
[[ -z $expected_version || $expected_version == v1 || $expected_version == v2 ]] || {
    echo "Usage: $0 [cluster-name] [v1|v2]" >&2
    exit 1
}
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/$cluster_name.yaml}"
[[ -f $KUBECONFIG ]] || export KUBECONFIG=$(k3d kubeconfig write "$cluster_name")

docker info >/dev/null
k3d cluster list
kubectl wait --for=condition=Ready nodes --all --timeout=120s
kubectl get namespaces argocd dev
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=120s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=120s
kubectl -n argocd get pods
kubectl -n dev rollout status deployment/wil-playground --timeout=60s
kubectl -n dev get deployment,pod,service
kubectl -n argocd get application playground
kubectl -n argocd get application playground -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}' |
    grep -Fx 'Synced Healthy'
kubectl -n argocd get application playground \
    -o jsonpath='{.spec.source.repoURL}{"\n"}{.spec.source.path}{"\n"}{.status.sync.revision}{"\n"}'

image=$(kubectl -n dev get deployment wil-playground -o jsonpath='{.spec.template.spec.containers[0].image}')
[[ $image == wil42/playground:v1 || $image == wil42/playground:v2 ]] || {
    echo "Unexpected Docker Hub image: $image" >&2
    exit 1
}
: "${expected_version:=${image##*:}}"
[[ $image == "wil42/playground:$expected_version" ]] || {
    echo "Expected $expected_version, deployment uses $image." >&2
    exit 1
}

response=$(curl --fail --silent --show-error --retry 20 --retry-all-errors --retry-delay 2 --max-time 10 http://127.0.0.1:8888/)
grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' <<<"$response"
grep -Eq "\"message\"[[:space:]]*:[[:space:]]*\"$expected_version\"" <<<"$response"
printf '%s\n' "$response"
echo "Part 3 is ready: Argo CD is Synced/Healthy and $expected_version answers on port 8888."
