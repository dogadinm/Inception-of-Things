#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

machine=$(vagrant status --machine-readable | awk -F, '$3 == "state" {print $2; exit}')
[[ "$machine" == *S ]] || { echo 'Expected the p2 server VM.' >&2; exit 1; }
node_name=$(printf '%s' "$machine" | tr '[:upper:]' '[:lower:]')

vagrant ssh "$machine" -c 'test "$(uname -m)" = x86_64 && sudo systemctl is-active --quiet k3s && ip -4 -o addr show | grep -F "192.168.56.110/24"'
vagrant ssh "$machine" -c "sudo /usr/local/bin/kubectl wait --for=condition=Ready node/$node_name --timeout=300s"
vagrant ssh "$machine" -c 'sudo /usr/local/bin/kubectl -n iot rollout status deployment/app1 --timeout=60s; sudo /usr/local/bin/kubectl -n iot rollout status deployment/app2 --timeout=60s; sudo /usr/local/bin/kubectl -n iot rollout status deployment/app3 --timeout=60s'
vagrant ssh "$machine" -c 'test "$(sudo /usr/local/bin/kubectl -n iot get deployment app2 -o jsonpath="{.spec.replicas}")" = 3'
vagrant ssh "$machine" -c 'sudo /usr/local/bin/kubectl get nodes -o wide; sudo /usr/local/bin/kubectl -n iot get deployments,services,ingress'
# Application readiness can precede Traefik/ServiceLB readiness on a fresh VM.
# Check the complete path from the host, including the default backend.
for route in app1.com:app1 app2.com:app2 other.example:app3 192.168.56.110:app3; do
    host=${route%%:*}
    expected=${route#*:}
    ready=false
    response=
    for ((attempt=0; attempt<60; attempt++)); do
        if response=$(curl --fail --silent --show-error --max-time 5 \
            -H "Host: $host" http://192.168.56.110/ 2>/dev/null) &&
            [[ $response == *"<h1>$expected</h1>"* ]]; then
            ready=true
            break
        fi
        sleep 2
    done
    [[ $ready == true ]] || {
        echo "HTTP routing failed: Host $host must return $expected." >&2
        printf '%s\n' "$response" >&2
        exit 1
    }
    echo "HTTP Host $host -> $expected: OK"
done
echo 'Part 2: K3s, three applications, and the Host-based Ingress are ready.'
