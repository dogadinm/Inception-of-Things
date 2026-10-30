#!/usr/bin/env bash
set -euo pipefail
umask 077
export PATH="/usr/local/bin:/usr/local/sbin:$PATH"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd -- "$script_dir/.." && pwd)
config_file=${1:-"$root_dir/confs/lab.env"}
[[ -f "$config_file" ]] || {
    echo "Copy confs/lab.env.example to confs/lab.env first." >&2
    exit 1
}
# shellcheck disable=SC1090
source "$config_file"
: "${K3D_CLUSTER_NAME:=iot}"
: "${GITLAB_IMAGE:=gitlab/gitlab-ce:19.5.3-ce.0}"
: "${GITLAB_PROJECT:=inception-of-things}"
: "${GITLAB_HOST_PORT:=8888}"
: "${ARGOCD_NAMESPACE:=argocd}"
[[ $K3D_CLUSTER_NAME =~ ^[a-z0-9][a-z0-9-]*$ &&
   $GITLAB_PROJECT =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ &&
   $GITLAB_IMAGE =~ ^gitlab/gitlab-ce:[a-zA-Z0-9._-]+$ &&
   $GITLAB_HOST_PORT =~ ^[0-9]+$ &&
   $ARGOCD_NAMESPACE == argocd ]] || {
    echo "Invalid lab configuration (this lab uses namespace argocd)." >&2
    exit 1
}
for tool in kubectl k3d docker curl jq; do
    command -v "$tool" >/dev/null || { echo "Missing $tool." >&2; exit 1; }
done
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/$K3D_CLUSTER_NAME.yaml}"
[[ -f $KUBECONFIG ]] || export KUBECONFIG=$(k3d kubeconfig write "$K3D_CLUSTER_NAME")
docker info >/dev/null
kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null
docker port "k3d-$K3D_CLUSTER_NAME-serverlb" 80/tcp | grep -q ":$GITLAB_HOST_PORT$" || {
    echo "Cluster must expose port $GITLAB_HOST_PORT:80@loadbalancer." >&2
    exit 1
}

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl -n gitlab get secret gitlab-credentials >/dev/null 2>&1; then
    root_password=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
    api_token=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
    kubectl -n gitlab create secret generic gitlab-credentials \
        --from-literal=root-password="$root_password" \
        --from-literal=api-token="$api_token" >/dev/null
fi
api_token=$(kubectl -n gitlab get secret gitlab-credentials -o jsonpath='{.data.api-token}' | base64 --decode)
sed "s|EXTERNAL_PORT_PLACEHOLDER|$GITLAB_HOST_PORT|g" "$root_dir/confs/gitlab.rb" > "$work_dir/gitlab.rb"
kubectl -n gitlab create configmap gitlab-config --from-file=gitlab.rb="$work_dir/gitlab.rb" \
    --dry-run=client -o yaml | kubectl apply -f -
sed -e "s|GITLAB_IMAGE_PLACEHOLDER|$GITLAB_IMAGE|g" \
    -e "s|CLUSTER_PLACEHOLDER|$K3D_CLUSTER_NAME|g" \
    "$root_dir/confs/gitlab.yaml.tpl" > "$work_dir/gitlab.yaml"
kubectl apply -f "$work_dir/gitlab.yaml"
echo "Waiting for GitLab initial database/configuration setup (up to 20 minutes)..."
kubectl -n gitlab rollout status statefulset/gitlab --timeout=1200s

# REST API requires a token, not HTTP Basic root/password authentication.
# Keep the token in Kubernetes Secrets and out of Git and normal output.
kubectl -n gitlab exec gitlab-0 -- env IOT_API_TOKEN="$api_token" gitlab-rails runner \
    "user=User.find_by!(username: 'root'); value=ENV.fetch('IOT_API_TOKEN'); token=PersonalAccessToken.find_by_token(value); if token; abort('Bootstrap token is expired, revoked or belongs to another user; replace api-token in gitlab-credentials') if token.user_id != user.id || token.revoked? || token.expired?; else; token=user.personal_access_tokens.create!(name: 'iot-bootstrap', scopes: ['api', 'read_repository', 'write_repository'], expires_at: 30.days.from_now.to_date); token.set_token(value); token.save!; end; puts 'IoT API token configured'"

api_url="http://127.0.0.1:$GITLAB_HOST_PORT/api/v4"
# A private curl config avoids putting the PAT into curl process arguments.
printf 'header = "PRIVATE-TOKEN: %s"\nheader = "Host: gitlab.local"\n' "$api_token" > "$work_dir/curl.conf"
api() { curl --config "$work_dir/curl.conf" --fail --silent --show-error --connect-timeout 5 --max-time 60 "$@"; }
api "$api_url/user" > /dev/null
project_json=$(api "$api_url/projects/root%2F$GITLAB_PROJECT" 2>/dev/null || true)
if [[ -z $project_json ]]; then
    project_json=$(api --request POST \
        --data-urlencode "name=$GITLAB_PROJECT" --data-urlencode "path=$GITLAB_PROJECT" \
        --data-urlencode 'visibility=public' --data-urlencode 'initialize_with_readme=true' \
        --data-urlencode 'default_branch=main' "$api_url/projects")
fi
project_id=$(jq -er '.id' <<<"$project_json")
[[ $(jq -r '.visibility' <<<"$project_json") == public ]] || {
    echo "GitLab project must be public for anonymous Argo CD reads." >&2
    exit 1
}

# Add missing files only. A rerun must preserve commits made during the demo.
actions='[]'
for file in deployment.yaml service.yaml ingress.yaml; do
    if api "$api_url/projects/$project_id/repository/files/gitops%2F$file?ref=main" >/dev/null 2>&1; then
        continue
    fi
    sed 's|wil42/playground:v2|wil42/playground:v1|g' "$root_dir/../p3/gitops/$file" > "$work_dir/$file"
    content=$(base64 < "$work_dir/$file" | tr -d '\n')
    actions=$(jq --arg path "gitops/$file" --arg content "$content" \
        '. + [{action:"create",file_path:$path,content:$content,encoding:"base64"}]' <<<"$actions")
done
if [[ $(jq length <<<"$actions") -gt 0 ]]; then
    jq -n --argjson actions "$actions" \
        '{branch:"main",commit_message:"Bootstrap GitOps application",actions:$actions}' > "$work_dir/commit.json"
    api --header 'Content-Type: application/json' --data-binary @"$work_dir/commit.json" \
        "$api_url/projects/$project_id/repository/commits" > /dev/null
fi

# Public local repository; Argo CD does not need an administrator token.
gitlab_repo_url="http://gitlab.gitlab.svc.cluster.local/root/$GITLAB_PROJECT.git"
sed "s|REPO_URL_PLACEHOLDER|$gitlab_repo_url|g" \
    "$root_dir/confs/argocd-application.yaml.tpl" > "$work_dir/application.yaml"
kubectl apply -f "$work_dir/application.yaml"
kubectl -n argocd annotate application playground argocd.argoproj.io/refresh=hard --overwrite
for ((attempt=0; attempt<120; attempt++)); do
    state=$(kubectl -n argocd get application playground \
        -o jsonpath='{.status.sync.status}{" "}{.status.health.status}' 2>/dev/null || true)
    if [[ $state == 'Synced Healthy' ]]; then
        break
    fi
    sleep 5
done
[[ $state == 'Synced Healthy' ]] || {
    kubectl -n argocd describe application playground >&2
    exit 1
}
"$script_dir/check.sh" "$K3D_CLUSTER_NAME"
echo "GitLab is ready: http://gitlab.local:$GITLAB_HOST_PORT (user root)."
echo "Get the password from Secret gitlab/gitlab-credentials (key root-password)."
