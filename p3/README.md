# Part 3 — K3d и Argo CD

## Что требуется по заданию

В p3 Vagrant не используется. В Linux VM запускаются Docker и кластер K3d
(K3s внутри контейнеров Docker). Argo CD автоматически разворачивает приложение
из публичного GitHub-репозитория.

- Namespace `argocd` содержит Argo CD, namespace `dev` — приложение.
- Используется образ Docker Hub `wil42/playground`, версии `v1` и `v2`.
- Приложение доступно на http://localhost:8888/.
- На защите нужно изменить тег в Git, сделать commit/push и показать обновление
  через Argo CD. Простое изменение Deployment командой kubectl этого не заменяет.
- Имя GitHub-репозитория должно содержать школьный логин участника.

K3s — дистрибутив Kubernetes; K3d запускает K3s в Docker. Namespace разделяет
ресурсы внутри кластера, pod запускает контейнеры приложения. Argo CD сравнивает
Git с кластером и применяет изменения автоматически (`automated`), исправляет
ручные отклонения (`selfHeal`) и удаляет удалённые из Git ресурсы (`prune`).

## Подготовка

Поддерживаются Linux x86_64 с apt-get, dnf или pacman, systemd, sudo и интернетом.
Перед запуском остановить VM p1/p2, чтобы освободить память. На защите использовать
среду, требуемую subject/eval sheet; локальный запуск на Arch проверяет работу.

В публичном GitHub-репозитории должен быть путь `p3/gitops`, содержащий
`deployment.yaml` и `service.yaml`. Репозиторий может содержать весь проект.
SSH-доступ нужен для push; Argo CD читает публичный HTTPS URL без SSH-ключей.
Не коммитить `.vagrant`, `.runtime`, `confs/lab.env`, пароли и eval sheet.

Команды ниже выполняются на Linux-машине, где работает Docker/K3d.
Из корня репозитория:

```sh
cd p3
cp confs/lab.env.example confs/lab.env
nano confs/lab.env
```

Указать настоящий URL и логин. Пример после создания/переименования репозитория:

```sh
GROUP_LOGIN=mdogadin
GIT_REPO_URL=https://github.com/dogadinm/Inception-of-Things-mdogadin.git
GIT_REPO_REVISION=main
K3D_CLUSTER_NAME=iot
K3D_VERSION=v5.8.3
ARGOCD_VERSION=v3.1.8
K3S_VERSION=v1.32.5-k3s1
KUBECTL_VERSION=v1.32.5
```

Пример URL не создаёт репозиторий: сначала проверить его существование
и публичность. Если имя не содержит `GROUP_LOGIN`, установщик завершится
с объяснением: это проверяемый пункт задания.

## Установка и запуск

Из `p3`:

```sh
sudo bash scripts/install.sh
```

Установщик ставит инструменты, запускает Docker, создаёт кластер с server,
agent и load balancer, namespaces, Argo CD и Application `playground`.
Версии K3s и kubectl зафиксированы в одном minor, чтобы избежать несовместимости.
Он ожидает готовности Argo CD и синхронизации приложения, затем сохраняет
пользовательский kubeconfig отдельным файлом, не заменяя существующий config.

Если пользователь только что добавлен в группу docker, выйти из сеанса Linux
и войти снова, чтобы применилось членство в группе. Затем:

```sh
export KUBECONFIG="$HOME/.kube/iot.yaml"
bash scripts/check.sh iot v1
```

Если кластер уже установлен, повторный запуск после остановки Docker/кластера:

```sh
sudo systemctl start docker
k3d cluster start iot
export KUBECONFIG="$HOME/.kube/iot.yaml"
bash scripts/check.sh
```

Если установка выполнялась вручную и отдельного kubeconfig ещё нет:

```sh
k3d kubeconfig get iot > "$HOME/.kube/iot.yaml"
chmod 600 "$HOME/.kube/iot.yaml"
export KUBECONFIG="$HOME/.kube/iot.yaml"
```

## Показ на защите: Configuration

Из `p3` показать файлы и объекты:

```sh
cat confs/lab.env.example
cat confs/argocd-application.yaml.tpl
cat gitops/deployment.yaml
cat gitops/service.yaml
k3d cluster list
docker ps
kubectl get nodes -o wide
kubectl get namespaces argocd dev
kubectl -n argocd get pods
kubectl -n dev get deployments,pods,services
kubectl -n argocd get application playground
```

Ожидается кластер `iot`, узлы Ready, namespaces Active, pod приложения Running,
Deployment `wil-playground` 1/1, Application `Synced` и `Healthy`.
В Deployment должен быть публичный Docker Hub образ `wil42/playground:v1`.
Открыть GitHub в браузере и показать публичность репозитория, логин в его имени,
ветку `main` и файл `p3/gitops/deployment.yaml`.

### Открыть Argo CD в браузере

В отдельном терминале, который оставить работающим:

```sh
export KUBECONFIG="$HOME/.kube/iot.yaml"
kubectl -n argocd port-forward --address 127.0.0.1 svc/argocd-server 8080:443
```

Открыть https://localhost:8080/. Сертификат лаборатории самоподписанный.
Логин `admin`. Пароль получить в другом терминале:

```sh
export KUBECONFIG="$HOME/.kube/iot.yaml"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
printf '\n'
```

Пароль не добавлять в Git. В интерфейсе открыть Application `playground`:
показать Repository URL, путь `p3/gitops`, ветку, commit SHA, Sync Status,
Health и дерево Deployment → ReplicaSet → Pod / Service.
При запуске внутри VM браузер должен быть в той же VM; localhost относится
к машине, где запущен port-forward.

## Показ на защите: Usage — v1 → v2 через GitHub

### 1. Показать v1

```sh
curl -f http://localhost:8888/
kubectl -n dev get deployment wil-playground -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Ожидается `{"status":"ok", "message":"v1"}` и образ `wil42/playground:v1`.
Если после предыдущей проверки оставлена v2, сначала таким же способом
ниже вернуть v1, commit/push, дождаться синхронизации и только затем показывать v2.

### 2. Изменить только файл Deployment и отправить в GitHub

Из каталога `p3`:

```sh
bash scripts/update-version.sh v2
git diff -- gitops/deployment.yaml
git add -- gitops/deployment.yaml
git diff --cached --name-only
git commit -m "Update playground to v2"
git push origin main
```

Перед commit проверить список staged: для демонстрации версии там должен быть
только `p3/gitops/deployment.yaml`. Не использовать `git add .`.
`git remote -v` должен указывать на репозиторий, который читает Argo CD.

### 3. Дождаться автоматического обновления

В Argo CD наблюдать новый commit и переход к `Synced / Healthy`.
Проверять в терминале (Ctrl+C завершает наблюдение):

```sh
kubectl -n argocd get application playground -w
```

Argo CD опрашивает Git периодически; обновление может занять несколько минут.
Если проверяющий просит обновить сведения о Git немедленно:

```sh
kubectl -n argocd annotate application playground argocd.argoproj.io/refresh=hard --overwrite
```

Эта команда обновляет сведения о Git, а применение выполняет автоматическая
политика Argo CD. В интерфейсе также доступны Refresh и, если требуется
проверочным листом, Sync.

### 4. Подтвердить v2

```sh
kubectl -n argocd get application playground -o jsonpath='{.status.sync.revision}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
git rev-parse HEAD
kubectl -n dev rollout status deployment/wil-playground --timeout=180s
kubectl -n dev get deployment wil-playground -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -f http://localhost:8888/
bash scripts/check.sh iot v2
```

SHA Argo CD должен соответствовать отправленному коммиту. Образ —
`wil42/playground:v2`, HTTP-ответ содержит `"message":"v2"`.
Rollout сам по себе не доказывает обновление: всегда сверять SHA, тег и ответ.

## Остановка, диагностика

```sh
k3d cluster stop iot
```

Для диагностики:

```sh
kubectl -n argocd describe application playground
kubectl -n argocd logs deploy/argocd-repo-server --tail=60
kubectl -n dev describe pod -l app.kubernetes.io/name=wil-playground
kubectl -n dev get events --sort-by=.lastTimestamp
```

`ImagePullBackOff`: проверить Docker Hub и сеть. `OutOfSync`/`Unknown`: URL,
публичность, ветку и путь в Git. Отказ на порту 8888: проверить Docker,
кластер и ServiceLB. Отказ на 8080: проверить процесс port-forward.
Для синтаксической проверки всех скриптов:

```sh
for script in scripts/*.sh; do bash -n "$script" || break; done
```
