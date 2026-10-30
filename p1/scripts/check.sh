#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Read names from Vagrant so a login change needs no edits to this script.
machines=$(vagrant status --machine-readable | awk -F, '$3 == "state" {print $2}')
server=
agent=
while IFS= read -r machine; do
    case "$machine" in *SW) agent=$machine ;; *S) server=$machine ;; esac
done <<< "$machines"
[[ -n $server && -n $agent ]] || { echo 'Expected a server and an agent.' >&2; exit 1; }

vagrant ssh "$server" -c 'test "$(uname -m)" = x86_64 && sudo systemctl is-active --quiet k3s && ip -4 -o addr show | grep -F "192.168.56.110/24"'
vagrant ssh "$agent" -c 'test "$(uname -m)" = x86_64 && sudo systemctl is-active --quiet k3s-agent && ip -4 -o addr show | grep -F "192.168.56.111/24"'

# Kubernetes node names are lowercase, while the subject's VM names end in S/SW.
server_node=$(printf '%s' "$server" | tr '[:upper:]' '[:lower:]')
agent_node=$(printf '%s' "$agent" | tr '[:upper:]' '[:lower:]')
vagrant ssh "$server" -c "sudo /usr/local/bin/kubectl wait --for=condition=Ready node/$server_node node/$agent_node --timeout=300s"
vagrant ssh "$server" -c 'sudo /usr/local/bin/kubectl get nodes -o wide; sudo /usr/local/bin/kubectl get pods -A'
vagrant ssh "$server" -c 'test "$(sudo /usr/local/bin/kubectl get nodes --no-headers | wc -l)" -eq 2'
echo 'Part 1: both x86_64 nodes are Ready and accessible over SSH.'
