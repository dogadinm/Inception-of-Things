# Part 1 — K3s and Vagrant

Two AlmaLinux VMs form one K3s cluster:

| Vagrant name / hostname | Private IP | Role | CPU | RAM |
| --- | --- | --- | --- | --- |
| mdogadinS | 192.168.56.110 | Server | 1 | 2048 MB |
| mdogadinSW | 192.168.56.111 | Agent | 1 | 1024 MB |

Each VM uses NAT for internet/forwarded SSH and host-only networking for cluster
traffic. VirtualBox names have a `p1-` prefix. Settings are in `confs/lab.yml`.
The server uses 2 GB after API timeouts with 1 GB; the subject recommends 512–1024 MB.

## Start

Use Linux x86_64 with x86-64-v2 CPU support, Vagrant, VirtualBox with working
kernel modules, and internet.
Use the school VM required by the evaluation sheet; nested virtualization is
needed if VirtualBox runs inside it. Check OS/box versions before evaluation.
**Stop p2 first:** both parts use 192.168.56.110. Run Vagrant without sudo.

From the repository root, on the host:

```sh
cd p1
bash scripts/up.sh
```

The script validates the configuration, starts the server before the agent,
and checks the cluster. Repeat the automated check with:

```sh
bash scripts/check.sh
```

## Manual checks

On the host, inside `p1`:

```sh
cat Vagrantfile
cat confs/lab.yml
vagrant validate
vagrant status
vagrant ssh mdogadinS
```

Wait for the VM prompt. Then run **inside the server**:

```sh
hostname
ip -4 a
ip route
sudo systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl get pods -A
exit
```

Expect hostname `mdogadinS`, private IP `.110`, active K3s and **two Ready nodes**
with IPs `.110` and `.111`. Kubernetes node names are lowercase; the agent's
ROLES column may show `<none>`.

Back on the host:

```sh
vagrant ssh mdogadinSW
```

Run **inside the worker**:

```sh
hostname
ip -4 a
sudo systemctl status k3s-agent --no-pager
exit
```

Expect `mdogadinSW`, private IP `.111`, and an active agent service.
Both SSH connections must work without a password.

## Stop, rebuild, or switch parts

Stop on the host from `p1` (keep VM disks):

```sh
vagrant halt
```

Start again and check:

```sh
bash scripts/up.sh
```

For a clean rebuild, `vagrant destroy` deletes both VM disks:

```sh
vagrant destroy
bash scripts/up.sh
```

Keep `.runtime/cluster-token` while either VM exists. Never commit `.runtime`
or `.vagrant`. Vagrant transfers the token and runs `scripts/provision.sh` over
SSH. The agent joins https://192.168.56.110:6443; Traefik, ServiceLB and
metrics-server are disabled in p1.

To switch to p2:

```sh
vagrant halt
cd ../p2
bash scripts/up.sh
```

## Troubleshooting

```sh
vagrant ssh mdogadinS -c 'sudo journalctl -u k3s -n 60 --no-pager'
vagrant ssh mdogadinSW -c 'sudo journalctl -u k3s-agent -n 60 --no-pager'
```

If ordinary kubectl prints config-directory permission warnings, use
`sudo /usr/local/bin/kubectl get nodes -o wide`.
For a hanging SSH session, press Ctrl+C, check `vagrant status`, then try
`vagrant reload` and `bash scripts/check.sh`.
