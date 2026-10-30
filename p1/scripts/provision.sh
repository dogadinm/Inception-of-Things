#!/usr/bin/env bash
set -euo pipefail
umask 077

role=${1:?Missing role}
node_ip=${2:?Missing node IP}
node_name=${3:?Missing Kubernetes node name}
k3s_version=${4:?Missing K3s version}
case "$role" in server|agent) ;; *) echo 'Invalid role' >&2; exit 1 ;; esac
[[ $EUID -eq 0 && $(uname -m) == x86_64 ]] || {
    echo 'Provisioning requires root inside an x86_64 guest.' >&2; exit 1;
}

service=k3s
[[ $role == server ]] || service=k3s-agent
trap 'echo "Provisioning failed; recent service logs:" >&2; journalctl -u "$service" -n 60 --no-pager >&2' ERR

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

# K3s owns the lab guests' pod networking. These changes affect guests only.
if systemctl list-unit-files firewalld.service --no-legend | grep -q '^firewalld'; then
    systemctl disable --now firewalld
fi
# AL10 SELinux policies are not yet a separate target in the K3s installer.
# Use permissive mode in this isolated exercise and skip the EL9 policy RPM.
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

# Detect the dedicated interface instead of assuming eth1/enp0s8.
interface=$(ip -o -4 addr show | awk -v target="$node_ip/24" '$4 == target {print $2; exit}')
[[ -n $interface ]] || { echo "No interface with $node_ip/24" >&2; exit 1; }

install -d -m 0700 /etc/rancher/k3s
install -m 0600 /tmp/iot-cluster-token /etc/rancher/k3s/token
rm -f /tmp/iot-cluster-token
cat > /etc/rancher/k3s/config.yaml <<EOF
node-name: "$node_name"
node-ip: "$node_ip"
flannel-iface: "$interface"
token-file: /etc/rancher/k3s/token
prefer-bundled-bin: true
EOF

if [[ $role == server ]]; then
    cat >> /etc/rancher/k3s/config.yaml <<EOF
advertise-address: "$node_ip"
tls-san:
  - "$node_ip"
write-kubeconfig-mode: "0600"
# Part 1 needs a cluster only; keep its memory usage low.
disable:
  - traefik
  - servicelb
  - metrics-server
EOF
else
    cat >> /etc/rancher/k3s/config.yaml <<'EOF'
server: https://192.168.56.110:6443
EOF
    echo 'Waiting for the server API at 192.168.56.110:6443...'
    available=false
    for ((attempt=0; attempt<120; attempt++)); do
        # Connectivity probe only; K3s performs authentication when joining.
        if curl -ksS --connect-timeout 2 --max-time 3 https://192.168.56.110:6443/ping >/dev/null; then
            available=true
            break
        fi
        sleep 5
    done
    [[ $available == true ]] || { echo 'Server API did not become reachable.' >&2; exit 1; }
fi

installer=$(mktemp)
curl -fsSL --retry 5 --connect-timeout 15 --max-time 120 https://get.k3s.io -o "$installer"
INSTALL_K3S_VERSION="$k3s_version" INSTALL_K3S_SKIP_SELINUX_RPM=true \
    INSTALL_K3S_EXEC="$role" sh "$installer"
rm -f "$installer"
# Config file changes alone do not make the upstream installer restart K3s.
systemctl restart "$service"

if [[ $role == server ]]; then
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
    # kubectl works as the SSH user without making admin credentials world-readable.
    install -d -o vagrant -g vagrant -m 0700 /home/vagrant/.kube
    install -o vagrant -g vagrant -m 0600 /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
    cat > /etc/profile.d/kubeconfig.sh <<'EOF'
export KUBECONFIG="$HOME/.kube/config"
EOF
    chmod 0644 /etc/profile.d/kubeconfig.sh
else
    systemctl is-active --quiet k3s-agent
fi
echo "Provisioned $role on $node_ip ($interface)."
