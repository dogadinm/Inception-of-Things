#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
    echo 'Run this lab on Linux x86_64 (the school computer).' >&2
    exit 1
fi
for tool in vagrant VBoxManage; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing $tool: install Vagrant and VirtualBox on the Linux host first." >&2
        exit 1
    fi
done
if ! VBoxManage list hostinfo >/dev/null; then
    echo 'VirtualBox is not usable. Check its kernel driver and your user permissions.' >&2
    exit 1
fi

vagrant validate
# Start the controller before provisioning the worker.
vagrant up --provider=virtualbox --no-parallel
./scripts/check.sh
