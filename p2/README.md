# Part 2 — K3s, three applications and Ingress

One AlmaLinux VM, `mdogadinS` at **192.168.56.110**, runs K3s server and Traefik.
It uses 1 CPU and 2048 MB RAM. Applications run in namespace `iot`:

| Application | Replicas | HTTP Host |
| --- | --- | --- |
| app1 | 1 | app1.com |
| app2 | 3 | app2.com |
| app3 | 1 | Any other Host, including the VM IP |

Request path: **Traefik / Ingress → Service → ready pod → nginx**.

## Start

Use Linux x86_64, Vagrant, VirtualBox with working kernel modules, curl and internet.
Use the school VM required for evaluation. Run Vagrant without sudo.
**Stop p1 first:** both parts use the same IP.

From the repository root, on the host:

```sh
cd p1
vagrant halt
cd ../p2
bash scripts/up.sh
```

For an existing p2 VM, reapply changed configuration and check:

```sh
vagrant provision
bash scripts/check.sh
```

## Configuration

```text
confs/
├── lab.yml
└── manifests/
    ├── namespace.yaml
    ├── app1.yaml       # ConfigMap + Deployment + Service
    ├── app2.yaml       # ConfigMap + Deployment + Service
    ├── app3.yaml       # ConfigMap + Deployment + Service
    └── ingress.yaml
```

Vagrant uploads these files over SSH. Provisioning creates the namespace first,
then applies the applications and Ingress. ConfigMaps provide nginx index.html
through subPath mounts. Pod labels connect Deployments and Services; Ingress
references Service names. The hostless Ingress rule routes unmatched Hosts to app3.

## Manual checks

On the host, inside `p2`:

```sh
cat Vagrantfile
cat confs/lab.yml
cat confs/manifests/app2.yaml
cat confs/manifests/ingress.yaml
vagrant validate
vagrant status
vagrant ssh mdogadinS
```

Wait for the VM prompt. Then run **inside the VM**:

```sh
hostname
ip -4 a
sudo systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl -n iot get all
kubectl -n iot get deployments
kubectl -n iot get replicasets
kubectl -n iot get pods -o wide
kubectl -n iot get pods -l app=app2
kubectl -n iot describe service app2
kubectl -n iot get endpointslices -l kubernetes.io/service-name=app2
kubectl -n iot describe ingress iot
exit
```

Expect hostname `mdogadinS`, IP `.110`, active K3s, one Ready node and **five
Running application pods**. Deployment readiness: app1 `1/1`, app2 `3/3`, app3 `1/1`.
The active app2 ReplicaSet should show DESIRED/CURRENT/READY `3/3/3`.

Run HTTP checks **on the host**:

```sh
curl -f -H 'Host: app1.com' http://192.168.56.110/
curl -f -H 'Host: app2.com' http://192.168.56.110/
curl -f -H 'Host: random.test' http://192.168.56.110/
curl -f http://192.168.56.110/
```

Expect **app1, app2, app3, app3**. Automated check: `bash scripts/check.sh`.
To show Ingress directly from the host:

```sh
vagrant ssh mdogadinS -c 'sudo /usr/local/bin/kubectl -n iot describe ingress iot'
```

## Browser

On the host, run `sudo nano /etc/hosts` and add missing names:

```text
192.168.56.110 app1.com app2.com
```

Open **http://app1.com/**, **http://app2.com/** and **http://192.168.56.110/**.
They should show app1, app2 and app3. hosts resolves names to the VM IP;
Ingress selects the application using the HTTP Host header. Use explicit HTTP.

## Optional: replace a pod

Inside the VM, copy one app2 pod name and replace `POD_NAME` below:

```sh
kubectl -n iot get pods -l app=app2
kubectl -n iot delete pod POD_NAME
kubectl -n iot get pods -l app=app2 -w
```

The ReplicaSet creates a replacement with a new name. Wait for three Ready pods;
press Ctrl+C to stop watching. Old ReplicaSets with zero pods may remain after updates.

## Stop and troubleshoot

On the host, inside `p2`:

```sh
vagrant halt                 # Stop and keep data
```

To rebuild from scratch, `vagrant destroy` deletes the VM disk; then run
`bash scripts/up.sh`. To switch to p1, halt p2, then `cd ../p1` and run its up script.

### Troubleshooting

```sh
vagrant ssh mdogadinS -c 'sudo journalctl -u k3s -n 60 --no-pager'
vagrant ssh mdogadinS -c 'sudo /usr/local/bin/kubectl -n kube-system get pods,svc'
```

For application errors, use `kubectl -n iot describe pod POD_NAME` and
`kubectl -n iot logs POD_NAME` inside the VM.
For hanging SSH, press Ctrl+C, run `vagrant status`, then `vagrant reload`
and `bash scripts/check.sh`. Use `bash scripts/up.sh` if the VM is stopped.
