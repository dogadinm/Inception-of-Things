#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd -- "$script_dir/.." && pwd)
config_file=${1:-"$root_dir/confs/lab.env"}
[[ -f "$config_file" ]] || {
    echo "Missing $config_file. Copy confs/lab.env.example to confs/lab.env." >&2
    exit 1
}
# shellcheck disable=SC1090
source "$config_file"
: "${K3D_CLUSTER_NAME:=iot}"
: "${GITLAB_RELEASE:=gitlab}"
: "${GITLAB_CHART_VERSION:=}"
: "${GITLAB_PROJECT:=inception-of-things}"
: "${GITLAB_HOST_PORT:=8888}"
: "${ARGOCD_NAMESPACE:=argocd}"

command -v kubectl >/dev/null || { echo "kubectl is required." >&2; exit 1; }
command -v k3d >/dev/null || { echo "k3d is required." >&2; exit 1; }
command -v docker >/dev/null || { echo "docker is required." >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required." >&2; exit 1; }
if ! command -v jq >/dev/null; then
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y jq
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y jq
    else
        echo "jq is required and no supported package manager was found." >&2
        exit 1
    fi
fi
if ! command -v helm >/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
export KUBECONFIG="${KUBECONFIG:-$(k3d kubeconfig write "$K3D_CLUSTER_NAME")}"
kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null || {
    echo "Argo CD namespace is missing. Complete Part 3 before the bonus." >&2
    exit 1
}

helm repo add gitlab https://charts.gitlab.io >/dev/null 2>&1 || true
helm repo update >/dev/null
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

helm_args=(
    upgrade --install "$GITLAB_RELEASE" gitlab/gitlab
    --namespace gitlab
    --create-namespace
    --timeout 20m
    --values "$root_dir/confs/values.yaml"
    --set "global.hosts.domain=gitlab.local"
    --set "global.ingress.class=traefik"
)
if [[ -n "$GITLAB_CHART_VERSION" ]]; then
    helm_args+=(--version "$GITLAB_CHART_VERSION")
fi
helm "${helm_args[@]}"

kubectl -n gitlab rollout status deployment/"$GITLAB_RELEASE-webservice-default" --timeout=900s
kubectl -n gitlab rollout status deployment/"$GITLAB_RELEASE-sidekiq-all-in-1" --timeout=900s

root_password=$(kubectl -n gitlab get secret "$GITLAB_RELEASE-gitlab-initial-root-password" \
    -o jsonpath='{.data.password}' | base64 --decode)
[[ -n "$root_password" ]] || { echo "GitLab root password is empty." >&2; exit 1; }

if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -Fxq "$K3D_CLUSTER_NAME"; then
    echo "K3d cluster '$K3D_CLUSTER_NAME' does not exist." >&2
    exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -Eq "^k3d-${K3D_CLUSTER_NAME}-serverlb$"; then
    echo "The K3d load balancer is not running." >&2
    exit 1
fi

if ! docker port "k3d-${K3D_CLUSTER_NAME}-serverlb" 80/tcp | grep -q ":$GITLAB_HOST_PORT"; then
    echo "GitLab is installed, but port $GITLAB_HOST_PORT is not exposed by K3d." >&2
    echo "Recreate the cluster with --port '$GITLAB_HOST_PORT:80@loadbalancer'." >&2
    exit 1
fi

api_url="http://127.0.0.1:$GITLAB_HOST_PORT/api/v4"
for ((attempt=0; attempt<120; attempt++)); do
    if curl --silent --fail --header "Host: gitlab.local" --user "root:$root_password" \
        "$api_url/user" >/dev/null; then
        break
    fi
    sleep 5
done
curl --silent --fail --header "Host: gitlab.local" --user "root:$root_password" \
    "$api_url/user" >/dev/null || {
    echo "GitLab API did not become available on port $GITLAB_HOST_PORT." >&2
    exit 1
}

project_json=$(curl --silent --fail --header "Host: gitlab.local" --user "root:$root_password" \
    "$api_url/projects/root%2F$GITLAB_PROJECT" 2>/dev/null || true)
if [[ -z "$project_json" || "$project_json" == "404 Project Not Found" ]]; then
    curl --silent --fail --header "Host: gitlab.local" --user "root:$root_password" \
        --data-urlencode "name=$GITLAB_PROJECT" --data-urlencode "path=$GITLAB_PROJECT" \
        --data-urlencode "namespace_id=1" "$api_url/projects" >/dev/null
fi

gitlab_repo_url="http://$GITLAB_RELEASE-webservice-default.gitlab.svc:8181/root/$GITLAB_PROJECT.git"
for file in deployment.yaml service.yaml; do
    content=$(base64 < "$root_dir/../p3/gitops/$file" | tr -d '\n')
    payload=$(jq -n --arg branch main --arg commit "Bootstrap $file" \
        --arg path "gitops/$file" --arg content "$content" \
        '{branch:$branch,commit_message:$commit,actions:[{action:"create",file_path:$path,content:$content,encoding:"base64"}]}')
    response=$(curl --silent --header "Host: gitlab.local" --user "root:$root_password" \
        --header 'Content-Type: application/json' --data "$payload" \
        --write-out '%{http_code}' "$api_url/projects/root%2F$GITLAB_PROJECT/repository/commits")
    if [[ "$response" != *201 ]]; then
        payload=$(jq -n --arg branch main --arg commit "Update $file" \
            --arg path "gitops/$file" --arg content "$content" \
            '{branch:$branch,commit_message:$commit,actions:[{action:"update",file_path:$path,content:$content,encoding:"base64"}]}')
        curl --silent --fail --header "Host: gitlab.local" --user "root:$root_password" \
            --header 'Content-Type: application/json' --data "$payload" \
            "$api_url/projects/root%2F$GITLAB_PROJECT/repository/commits" >/dev/null
    fi
done

kubectl -n "$ARGOCD_NAMESPACE" create secret generic gitlab-repository \
    --from-literal=type=git \
    --from-literal=url="$gitlab_repo_url" \
    --from-literal=username=root \
    --from-literal=password="$root_password" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" label secret gitlab-repository argocd.argoproj.io/secret-type=repository --overwrite

argocd_manifest=$(mktemp)
trap 'rm -f "$argocd_manifest"' EXIT
sed "s|REPO_URL_PLACEHOLDER|$gitlab_repo_url|g" \
    "$root_dir/confs/argocd-application.yaml.tpl" > "$argocd_manifest"
kubectl apply -f "$argocd_manifest"

kubectl -n argocd get application playground -o jsonpath='{.metadata.name}{"\n"}'
echo "GitLab is running in namespace gitlab."
echo "Open http://127.0.0.1:$GITLAB_HOST_PORT with Host: gitlab.local."
echo "Argo CD now reads the local GitLab repository: $gitlab_repo_url"
