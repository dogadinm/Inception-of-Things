# Inception of Things

Vagrant, K3s, K3d and GitOps with Argo CD.

| Part | Infrastructure | Defense guide |
|---|---|---|
| p1 | Two Vagrant VMs: K3s server and agent | [Start and checks](p1/README.md) |
| p2 | One Vagrant VM: three web applications and Ingress | [Start and checks](p2/README.md) |
| p3 | K3s in Docker with K3d; deploy from GitHub using Argo CD | [Start and checks](p3/README.md) |
| bonus | Local GitLab in the same K3d cluster; deploy from GitLab | [Start and checks](bonus/README.md) |

## Run order

Use the 42 VM required by the evaluation sheet. For p1/p2, VirtualBox needs
working kernel modules and nested virtualization when running inside a VM.
Use Linux x86_64 with x86-64-v2 CPU support, internet, sudo, Vagrant and VirtualBox.
The p3 installer installs Docker and its required tools.

From the repository root, run one part at a time:

```bash
cd p1
bash scripts/up.sh
# Follow p1/README.md, then stop both VMs:
vagrant halt
cd ../p2
bash scripts/up.sh
# Follow p2/README.md, then stop its VM:
vagrant halt
```

Do not run p1 and p2 together: both use `192.168.56.110`.
For p3, follow its first-install instructions, demonstrate GitHub v1 → v2,
then install the bonus in the same cluster and repeat using local GitLab.

## Command locations

- Run Vagrant commands in `p1/` or `p2/` on the machine hosting those VMs, without sudo.
- After `vagrant ssh`, wait for the guest prompt before typing guest commands.
  `exit` returns to the host.
- Run Docker/K3d/kubectl commands on the Linux machine hosting the K3d cluster.
  In each new terminal, use `export KUBECONFIG="$HOME/.kube/iot.yaml"`.
- Each part's README states its working directory. Do not mix GitHub and GitLab
  working copies: Argo CD source and the destination of `git push` are separate settings.

## Before defense

- Clone the submitted repository into an empty directory on the required machine.
- The public GitHub repository **name must contain a member's school login**.
  The current name `Inception-of-Things` does not meet that requirement. After
  renaming, update the Git remote, `p3/confs/lab.env` and the Argo CD source.
- Verify the latest stable OS and GitLab versions before the defense.
- Start the application at v1, then demonstrate a committed v2 change and its
  HTTP response. Use GitHub for p3 and local GitLab for the bonus.
- Be ready to explain every file, K3s vs K3d, Vagrant provisioning, namespaces vs
  Pods, Service/Ingress, CI vs continuous delivery, and Argo CD synchronization.
- Evaluate the bonus only after the mandatory parts pass completely.

Do not commit local `lab.env`, `.vagrant`, `.runtime`, credentials or the evaluation
sheet. Stopping preserves data; destroying VMs or deleting the cluster can remove it.

See [the verification notes](VERIFICATION.md) for the latest audit and remaining checks.
