#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd -- "$script_dir/.." && pwd)
if [[ -f "$root_dir/confs/lab.env" ]]; then
    # shellcheck disable=SC1091
    source "$root_dir/confs/lab.env"
fi
cluster_name=${1:-${K3D_CLUSTER_NAME:-iot}}
expected_version=${2:-}
: "${GITLAB_PROJECT:=inception-of-things}"
: "${GITLAB_HOST_PORT:=8888}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/$cluster_name.yaml}"
[[ -f $KUBECONFIG ]] || export KUBECONFIG=$(k3d kubeconfig write "$cluster_name")

kubectl get namespace gitlab
kubectl -n gitlab rollout status statefulset/gitlab --timeout=120s
kubectl -n gitlab get pods,services,ingress,pvc
kubectl -n gitlab exec gitlab-0 -- head -n 1 /opt/gitlab/version-manifest.txt
curl --fail --silent --show-error --max-time 20 --header 'Host: gitlab.local' \
    "http://127.0.0.1:$GITLAB_HOST_PORT/-/readiness"
printf '\n'
project_json=$(curl --fail --silent --show-error --max-time 20 --header 'Host: gitlab.local' \
    "http://127.0.0.1:$GITLAB_HOST_PORT/api/v4/projects/root%2F$GITLAB_PROJECT")
jq -e --arg expected "root/$GITLAB_PROJECT" \
    '.path_with_namespace == $expected and .visibility == "public"' <<<"$project_json" >/dev/null
repo_url=$(kubectl -n argocd get application playground -o jsonpath='{.spec.source.repoURL}')
[[ $repo_url == "http://gitlab.gitlab.svc.cluster.local/root/$GITLAB_PROJECT.git" ]] || {
    echo "Argo CD must read the LOCAL GitLab project; actual source: $repo_url" >&2
    exit 1
}
[[ $(kubectl -n argocd get application playground -o jsonpath='{.spec.source.path}') == gitops ]] || {
    echo "Expected GitLab GitOps path gitops." >&2
    exit 1
}
project_id=$(jq -er '.id' <<<"$project_json")
expected_sha=$(curl --fail --silent --show-error --max-time 20 --header 'Host: gitlab.local' \
    "http://127.0.0.1:$GITLAB_HOST_PORT/api/v4/projects/$project_id/repository/branches/main" | jq -er '.commit.id')
kubectl -n argocd wait --for="jsonpath={.status.sync.revision}=$expected_sha" application/playground --timeout=300s
kubectl -n argocd wait --for='jsonpath={.status.sync.status}=Synced' application/playground --timeout=300s
kubectl -n argocd wait --for='jsonpath={.status.health.status}=Healthy' application/playground --timeout=300s
"$root_dir/../p3/scripts/check.sh" "$cluster_name" "$expected_version"
echo 'Bonus is ready: local GitLab is running and Argo CD deploys from its repository.'
