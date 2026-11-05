# Bonus — Local GitLab

Run commands from **`bonus/`** on the Linux machine running Docker/K3d.
Complete the mandatory parts first; use the 42 VM required by the evaluation sheet.

## 1. Start / install

Requires a working p3 cluster, Docker access, kubectl, curl and jq.
GitLab needs additional RAM and disk space; the configured memory limit is 4 GiB
and its storage request is 30 GiB. Stop unused p1/p2 VMs.

For an existing installation:

```bash
sudo systemctl start docker
k3d cluster start iot
export KUBECONFIG="$HOME/.kube/iot.yaml"
kubectl -n gitlab get statefulsets,pods,services,ingress,pvc
```

Expected: StatefulSet 1/1, Pod `gitlab-0` ready and Running, PVC Bound.
If previously scaled down:

```bash
kubectl -n gitlab scale statefulset gitlab --replicas=1
kubectl -n gitlab rollout status statefulset/gitlab --timeout=1200s
```

For first installation instead, prepare the config and run the installer:

```bash
cp confs/lab.env.example confs/lab.env
nano confs/lab.env
bash scripts/install.sh
```

Defaults: cluster `iot`, project `inception-of-things`, host port `8888`.
Initial setup can take 10–20 minutes. It creates GitLab, credentials, a public
local repository with `gitops/`, and switches Argo CD to it. Reruns preserve
existing Git commits. Do not overwrite an existing `lab.env` just to restart.

## 2. Open GitLab and create a repository

On the machine with the browser, check name resolution:

```bash
getent hosts gitlab.local
```

If missing, add this line using `sudo nano /etc/hosts`:

```text
127.0.0.1 gitlab.local
```

Open **http://gitlab.local:8888**. Username: `root`. Get the password:

```bash
kubectl -n gitlab get secret gitlab-credentials \
  -o jsonpath='{.data.root-password}' | base64 -d
echo
```

For defense, demonstrate repository creation and adding code:

1. New project → Create blank project.
2. Name it `defense-test` in the personal namespace `root` and initialize a README.
3. Add `hello.py` through the web editor, containing `print("Hello from GitLab")`.
4. Commit the file and show the file and commit in the project.

Do not commit passwords or tokens. With a browser outside the VM, use the VM
address and configure port access; `localhost` refers to the browser's machine.

## 3. Switch Argo CD from GitHub to GitLab

For the default project, run from `bonus/`:

```bash
sed \
  -e 's|REPO_URL_PLACEHOLDER|http://gitlab.gitlab.svc.cluster.local/root/inception-of-things.git|g' \
  confs/argocd-application.yaml.tpl | kubectl apply -f -
kubectl -n argocd annotate application playground \
  argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get application playground \
  -o jsonpath='{.spec.source.repoURL}{"\n"}{.spec.source.path}{"\n"}'
kubectl -n argocd get application playground
```

Expected source: `http://gitlab.gitlab.svc.cluster.local/root/inception-of-things.git`,
path `gitops`, then `Synced / Healthy`. Adjust the URL if using a different project.
The internal Service name works inside Kubernetes; the browser uses
**http://gitlab.local:8888/root/inception-of-things**.

## 4. Demonstrate v1 → v2

Open `root/inception-of-things` → `gitops/deployment.yaml` in GitLab.
Ensure the image is `wil42/playground:v1`; if necessary, edit and commit to `main`,
then wait for Argo CD to deploy v1:

```bash
curl -f http://localhost:8888/
bash scripts/check.sh iot v1
```

Expected response: `{"status":"ok", "message":"v1"}`.

Edit the same file in **GitLab**, change the image to `wil42/playground:v2`, and
commit to `main`. A web commit is already saved on the Git server; no local push
is needed. Alternatively, clone this GitLab repository and commit/push normally;
for HTTP push, use a Personal Access Token with `write_repository` as the password.
Do not change GitHub or manually apply the Deployment for this demonstration.

Watch automatic synchronization in Argo CD or the terminal:

```bash
kubectl -n argocd get application playground -w
```

Allow a few minutes for polling; Ctrl+C stops watching. If necessary, use Refresh
and then Sync in the UI. See [p3](../p3/README.md#argo-cd-ui) for UI access.

Verify the revision against the commit shown in GitLab, image and response:

```bash
kubectl -n argocd get application playground \
  -o jsonpath='{.status.sync.revision}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
kubectl -n dev get deployment wil-playground \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -f http://localhost:8888/
bash scripts/check.sh iot v2
```

Expected: matching GitLab commit, `Synced / Healthy`, image v2, HTTP message v2.
The bonus checker also verifies that Argo CD reads local GitLab.

## Files and architecture

| File | Purpose |
|---|---|
| `confs/lab.env` | Cluster, image, project and port |
| `confs/gitlab.yaml.tpl` | StatefulSet, Service, Ingress and persistent storage |
| `confs/gitlab.rb` | GitLab URL and settings for reduced memory usage |
| `confs/argocd-application.yaml.tpl` | Local GitLab source, branch main, path gitops |
| `scripts/install.sh` | Install/configure GitLab, create repository, configure Argo CD |
| `scripts/check.sh` | Verify GitLab, Git revision and application version |

```text
Same K3d cluster:
  gitlab namespace → GitLab Pod + persistent volume
  argocd namespace → Argo CD
  dev namespace    → playground

Update:  GitLab commit → Argo CD → Deployment → new application Pod
Browser: gitlab.local:8888 → Traefik → GitLab Service → GitLab Pod
         localhost:8888   → Traefik → playground Service → playground Pod
```

One official GitLab CE container runs GitLab and its supporting services.
StatefulSet maintains `gitlab-0`; PVC preserves its repositories and database
across Pod replacement. Secrets hold the generated password and API token.
The installed image version is configured in `lab.env`; verify the required
version before defense.

## Troubleshoot / return to p3 / stop

```bash
kubectl -n gitlab describe pod gitlab-0
kubectl -n gitlab logs gitlab-0 --tail=80
kubectl -n argocd describe application playground
```

To restore GitHub, first check that `../p3/confs/lab.env` has the correct URL:

```bash
source ../p3/confs/lab.env
sed -e "s|REPO_URL_PLACEHOLDER|$GIT_REPO_URL|g" \
    -e "s|REVISION_PLACEHOLDER|$GIT_REPO_REVISION|g" \
    ../p3/confs/argocd-application.yaml.tpl | kubectl apply -f -
kubectl -n argocd annotate application playground \
  argocd.argoproj.io/refresh=hard --overwrite
```

Wait for GitHub synchronization before stopping only GitLab:

```bash
kubectl -n gitlab scale statefulset gitlab --replicas=0
```

Or stop the entire cluster while preserving its state:

```bash
k3d cluster stop iot
```

Deleting the cluster can destroy the local GitLab data. On another machine,
install again; local repositories and credentials are not transferred automatically.
