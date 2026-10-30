#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
    echo 'Run this lab on Linux x86_64 (the school computer).' >&2
    exit 1
fi
for tool in vagrant VBoxManage curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing $tool: install Vagrant, VirtualBox and curl on the Linux host first." >&2
        exit 1
    fi
done
VBoxManage list hostinfo >/dev/null || {
    echo 'VirtualBox is not usable. Check its kernel driver and your user permissions.' >&2
    exit 1
}

vagrant validate
vagrant up --provider=virtualbox
./scripts/check.sh
