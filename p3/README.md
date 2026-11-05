# Part 3 — K3d and Argo CD

Run commands from **`p3/`**, on the Linux machine running Docker.
For defense, use the 42 VM required by the evaluation sheet.
The public GitHub repository **name must contain a member's school login**;
`Inception-of-Things` needs renaming before defense. Update the Git remote and
`confs/lab.env` after renaming.

## Start

Existing installation:

```bash
sudo systemctl start docker
k3d cluster start iot
export KUBECONFIG="$HOME/.kube/iot.yaml"
```

First installation instead: copy `confs/lab.env.example` to `confs/lab.env`, set
login, actual public GitHub URL and branch, then run:

```bash
sudo bash scripts/install.sh
export KUBECONFIG="$HOME/.kube/iot.yaml"
```

## Configuration checks

```bash
k3d cluster list
kubectl get nodes -o wide
kubectl get namespaces argocd dev
kubectl -n argocd get pods -o wide
kubectl -n dev get deployments,pods,services,ingress
kubectl -n argocd get application playground
kubectl -n argocd get application playground \
  -o jsonpath='{.spec.source.repoURL}{"\n"}{.spec.source.targetRevision}{"\n"}{.spec.source.path}{"\n"}'
```

Expected: Ready nodes, running Pods, source GitHub / `main` / `p3/gitops`, and
Application `Synced / Healthy`. Show the public repository and its image
`wil42/playground` on GitHub; Docker Hub provides tags `v1` and `v2`.

If returning from the GitLab bonus, restore the GitHub source using `lab.env`:

```bash
source confs/lab.env
sed -e "s|REPO_URL_PLACEHOLDER|$GIT_REPO_URL|g" \
    -e "s|REVISION_PLACEHOLDER|$GIT_REPO_REVISION|g" \
    confs/argocd-application.yaml.tpl | kubectl apply -f -
```

## Argo CD UI

In a separate terminal, keep running:

```bash
export KUBECONFIG="$HOME/.kube/iot.yaml"
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open **https://localhost:8080** on that machine; accept the lab certificate.
Username: `admin`. Get the password in the original terminal:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
```

Open `playground`: explain its Git source, commit and resource tree.
`Synced` means configuration matches Git; `Healthy` means resources are healthy.

## Demonstrate v1 → v2

Start with v1. If currently on v2, use the change/commit/push sequence below with
`v1` first and wait for the v1 response.

```bash
curl -f http://localhost:8888/
```

Expected: `{"status":"ok", "message":"v1"}`. Then update through GitHub:

```bash
bash scripts/update-version.sh v2
git diff -- gitops/deployment.yaml
git remote -v
git add -- gitops/deployment.yaml
git diff --cached --name-only
git commit -m "Update playground to v2"
git push origin main
kubectl -n argocd get application playground -w
```

The push remote must match the Application repository. Stage only the Deployment
file. Do not apply it manually. Allow a few minutes for Git polling; Ctrl+C stops
watching. If needed, use Refresh and then Sync in the Argo CD UI.

```bash
git rev-parse HEAD
kubectl -n argocd get application playground \
  -o jsonpath='{.status.sync.revision}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
kubectl -n dev get deployment wil-playground \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -f http://localhost:8888/
bash scripts/check.sh iot v2
```

Expected: matching commit SHA, `Synced / Healthy`, image `wil42/playground:v2`,
and response containing `"message":"v2"`.

## Explain the files

| File | Purpose |
|---|---|
| `confs/lab.env` | Versions, cluster name, Git URL and branch |
| `scripts/install.sh` | Install tools, create K3d and install Argo CD |
| `confs/argocd-application.yaml.tpl` | Git source, target namespace and sync policy |
| `gitops/deployment.yaml` | Image, replicas, Pod labels and health checks |
| `gitops/service.yaml` | Select ready Pods; port 80 → Pod port 8888 |
| `gitops/ingress.yaml` | Traefik routing rules |
| `scripts/update-version.sh` | Change local image tag |
| `scripts/check.sh` | Check cluster, Argo CD and HTTP response |

K3d runs K3s nodes inside Docker. A namespace groups objects; a Pod runs containers
on one node. Argo CD continuously deploys Git state (GitOps); CI builds/tests code.
`automated` applies Git changes, `selfHeal` repairs drift, `prune` removes managed
objects deleted from Git.

```text
Update:  GitHub → Argo CD → Kubernetes → Deployment → ReplicaSet → Pod
Traffic: localhost:8888 → serverlb → Traefik → Service:80 → Pod:8888
                                   (Ingress rules)
```

## Troubleshoot / stop

```bash
kubectl -n argocd describe application playground
kubectl -n dev describe pod -l app.kubernetes.io/name=wil-playground
kubectl -n dev logs deployment/wil-playground
```

For stale Git data / `not our ref`, request a hard refresh:

```bash
kubectl -n argocd annotate application playground \
  argocd.argoproj.io/refresh=hard --overwrite
```

Stop port-forward with Ctrl+C. Preserve the cluster and its data:

```bash
k3d cluster stop iot
```
