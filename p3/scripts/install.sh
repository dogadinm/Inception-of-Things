#!/usr/bin/env bash
set -euo pipefail
umask 022

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd -- "$script_dir/.." && pwd)
config_file=${1:-"$root_dir/confs/lab.env"}

[[ $EUID -eq 0 ]] || {
    echo "Run this script as root: sudo $0 [path/to/lab.env]." >&2
    exit 1
}
[[ -f "$config_file" ]] || {
    echo "Missing $config_file. Copy confs/lab.env.example to confs/lab.env first." >&2
    exit 1
}
# shellcheck disable=SC1090
source "$config_file"
: "${GIT_REPO_URL:?GIT_REPO_URL is required}"
: "${GROUP_LOGIN:?GROUP_LOGIN is required}"
: "${GIT_REPO_REVISION:=main}"
: "${K3D_CLUSTER_NAME:=iot}"
: "${K3D_VERSION:=v5.8.3}"
: "${ARGOCD_VERSION:=v3.1.8}"

[[ $GIT_REPO_URL =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]] || {
    echo "GIT_REPO_URL must be a public HTTPS GitHub repository URL." >&2
    exit 1
}
repo_name=${GIT_REPO_URL##*/}
repo_name=${repo_name%.git}
[[ "$repo_name" == *"$GROUP_LOGIN"* ]] || {
    echo "The GitHub repository name must contain GROUP_LOGIN ($GROUP_LOGIN)." >&2
    exit 1
}
[[ $GIT_REPO_REVISION =~ ^[A-Za-z0-9._/-]+$ ]] || {
    echo "GIT_REPO_REVISION contains unsupported characters." >&2
    exit 1
}
[[ $K3D_CLUSTER_NAME =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
    echo "K3D_CLUSTER_NAME must contain lowercase letters, digits and hyphens." >&2
    exit 1
}

if command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl git
    if ! command -v docker >/dev/null 2>&1; then
        dnf install -y dnf-plugins-core
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ca-certificates curl git docker.io
else
    echo "Unsupported distribution: expected dnf or apt-get." >&2
    exit 1
fi

systemctl enable --now docker
usermod -aG docker "${SUDO_USER:-vagrant}" 2>/dev/null || true

if ! command -v k3d >/dev/null 2>&1 || [[ "$(k3d version 2>/dev/null | head -1)" != *"$K3D_VERSION"* ]]; then
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG="$K3D_VERSION" bash
fi

if ! command -v kubectl >/dev/null 2>&1; then
    kubectl_version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$kubectl_version/bin/linux/amd64/kubectl"
    chmod 0755 /usr/local/bin/kubectl
fi

if ! command -v argocd >/dev/null 2>&1; then
    curl -fsSLo /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-linux-amd64"
    install -m 0755 /tmp/argocd /usr/local/bin/argocd
    rm -f /tmp/argocd
fi

if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -Fxq "$K3D_CLUSTER_NAME"; then
    k3d cluster create "$K3D_CLUSTER_NAME" \
        --agents 1 \
        --wait \
        --port "8888:80@loadbalancer"
fi

export KUBECONFIG=$(k3d kubeconfig write "$K3D_CLUSTER_NAME")
kubectl apply -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

argocd_manifest=$(mktemp)
trap 'rm -f "$argocd_manifest"' EXIT
sed \
    -e "s|REPO_URL_PLACEHOLDER|$GIT_REPO_URL|g" \
    -e "s|REVISION_PLACEHOLDER|$GIT_REPO_REVISION|g" \
    "$root_dir/confs/argocd-application.yaml.tpl" > "$argocd_manifest"
kubectl apply -f "$argocd_manifest"
for ((attempt=0; attempt<120; attempt++)); do
    app_state=$(kubectl -n argocd get application playground \
        -o jsonpath='{.status.sync.status}{" "}{.status.health.status}' 2>/dev/null || true)
    if [[ "$app_state" == "Synced Healthy" ]]; then
        break
    fi
    sleep 5
done
[[ "$app_state" == "Synced Healthy" ]] || {
    echo "Argo CD application did not become Synced/Healthy: $app_state" >&2
    kubectl -n argocd get application playground -o yaml >&2
    exit 1
}
kubectl -n dev rollout status deployment/wil-playground --timeout=300s

install -d -m 0755 /etc/profile.d
cat > /etc/profile.d/iot-k3d.sh <<EOF
export KUBECONFIG="$HOME/.kube/config"
EOF
echo "K3d cluster '$K3D_CLUSTER_NAME' and Argo CD application are ready."
echo "Test with: curl http://localhost:8888/"
