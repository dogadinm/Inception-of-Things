#!/usr/bin/env bash
set -euo pipefail
umask 077

node_ip=${1:?Missing node IP}
node_name=${2:?Missing Kubernetes node name}
k3s_version=${3:?Missing K3s version}
[[ $EUID -eq 0 && $(uname -m) == x86_64 ]] || {
    echo 'Provisioning requires root inside an x86_64 guest.' >&2
    exit 1
}

trap 'echo "Provisioning failed; recent service logs:" >&2; journalctl -u k3s -n 60 --no-pager >&2' ERR
# Vagrant's readiness probes share the VirtualBox NAT gateway address.
# Exempt only that lab gateway from OpenSSH's unauthenticated-probe penalties.
install -d -m 0755 /etc/ssh/sshd_config.d
echo 'PerSourcePenaltyExemptList 10.0.2.2/32' > /etc/ssh/sshd_config.d/60-iot-vagrant.conf
/usr/sbin/sshd -t
systemctl reload sshd

dnf install -y curl ca-certificates iproute
# The minimal AlmaLinux 10 box omits bridge netfilter from its base modules.
# Match the running kernel so the module can be loaded without a reboot.
dnf install -y "kernel-modules-extra-$(uname -r)"

if systemctl list-unit-files firewalld.service --no-legend | grep -q '^firewalld'; then
    systemctl disable --now firewalld
fi
if command -v getenforce >/dev/null && [[ $(getenforce) != Disabled ]]; then
    setenforce 0
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
fi

swapoff -a
sed -i '/^[^#].*[[:space:]]swap[[:space:]]/s/^/# /' /etc/fstab
cat > /etc/modules-load.d/k3s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat > /etc/sysctl.d/90-k3s.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system >/dev/null

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/90-k3s.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:cni*;interface-name:flannel*
EOF
systemctl reload NetworkManager

interface=$(ip -o -4 addr show | awk -v target="$node_ip/24" '$4 == target {print $2; exit}')
[[ -n $interface ]] || { echo "No interface with $node_ip/24" >&2; exit 1; }

install -d -m 0700 /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<EOF
node-name: "$node_name"
node-ip: "$node_ip"
flannel-iface: "$interface"
advertise-address: "$node_ip"
tls-san:
  - "$node_ip"
write-kubeconfig-mode: "0600"
EOF

installer=$(mktemp)
trap 'rm -f "$installer"; echo "Provisioning failed; recent service logs:" >&2; journalctl -u k3s -n 60 --no-pager >&2' ERR
curl -fsSL --retry 5 --connect-timeout 15 --max-time 120 https://get.k3s.io -o "$installer"
INSTALL_K3S_VERSION="$k3s_version" INSTALL_K3S_SKIP_SELINUX_RPM=true \
    INSTALL_K3S_EXEC="server" sh "$installer"
rm -f "$installer"
systemctl restart k3s

ready=false
for ((attempt=0; attempt<120; attempt++)); do
    if /usr/local/bin/kubectl --request-timeout=10s get --raw=/readyz >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 5
done
[[ $ready == true ]] || { echo 'Kubernetes API did not become ready.' >&2; exit 1; }
/usr/local/bin/kubectl wait --for=create "node/$node_name" --timeout=300s
/usr/local/bin/kubectl wait --for=condition=Ready "node/$node_name" --timeout=300s

/usr/local/bin/kubectl apply -f /tmp/iot-apps.yaml
rm -f /tmp/iot-apps.yaml
/usr/local/bin/kubectl rollout status deployment/app1 --namespace=iot --timeout=300s
/usr/local/bin/kubectl rollout status deployment/app2 --namespace=iot --timeout=300s
/usr/local/bin/kubectl rollout status deployment/app3 --namespace=iot --timeout=300s

install -d -o vagrant -g vagrant -m 0700 /home/vagrant/.kube
install -o vagrant -g vagrant -m 0600 /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
cat > /etc/profile.d/kubeconfig.sh <<'EOF'
export KUBECONFIG="$HOME/.kube/config"
EOF
chmod 0644 /etc/profile.d/kubeconfig.sh
echo "Provisioned K3s server on $node_ip ($interface) with three applications."
