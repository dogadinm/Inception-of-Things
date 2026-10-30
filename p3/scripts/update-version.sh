#!/usr/bin/env bash
set -euo pipefail

version=${1:-}
[[ "$version" == v1 || "$version" == v2 ]] || {
    echo "Usage: $0 v1|v2" >&2
    exit 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd -- "$script_dir/.." && pwd)
sed -i.bak -E "s|(image:[[:space:]]+wil42/playground:)v[12]|\1$version|" \
    "$root_dir/gitops/deployment.yaml"
rm -f "$root_dir/gitops/deployment.yaml.bak"
grep -F "image: wil42/playground:$version" "$root_dir/gitops/deployment.yaml"
echo "Commit and push this change to GitHub; Argo CD will synchronize it automatically."
