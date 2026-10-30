# Part 3 — K3d и Argo CD

## Цель Part 3

В этой части Vagrant не используется. На уже доступной Linux-виртуальной
машине создаётся локальный Kubernetes-кластер K3d, а Argo CD управляет
приложением из публичного GitHub-репозитория.

Конфигурация соответствует требованиям задания:

- namespace `argocd` предназначен для Argo CD;
- namespace `dev` содержит приложение;
- приложение использует публичный образ `wil42/playground`;
- доступны версии образа `v1` и `v2`;
- версия меняется в GitHub, после чего Argo CD автоматически синхронизирует
  Deployment;
- приложение доступно на `http://localhost:8888/`.

### K3s и K3d

K3s — лёгкая дистрибуция Kubernetes. В Part 2 она запускалась непосредственно
в гостевой системе как systemd-сервис и управляла контейнерами на этой машине.

K3d не является другой реализацией Kubernetes. Это инструмент, который
запускает K3s внутри Docker-контейнеров. Поэтому в Part 3:

1. Docker предоставляет контейнерный runtime;
2. K3d создаёт server-, agent- и load balancer-контейнеры;
3. Kubernetes API и workload работают внутри Docker-сети;
4. проброс `8888:80` связывает порт хоста с load balancer K3d.

Такой подход позволяет быстро создать и удалить учебный кластер без Vagrant.

## Обязательная подготовка GitHub

По условию нужен **public GitHub repository**, в имени которого присутствует
логин участника группы. Например:

```text
https://github.com/mdogadin/inception-of-things-mdogadin.git
```

Репозиторий должен содержать каталог `p3/gitops` из этого проекта. После
создания репозитория выполните в каталоге проекта:

```sh
git remote add p3-git https://github.com/USERNAME/REPOSITORY_WITH_LOGIN.git
git push p3-git main
```

Если репозиторий уже содержит другую структуру, убедитесь, что в его корне
есть именно `p3/gitops/deployment.yaml` и `p3/gitops/service.yaml`. Argo CD
читает путь `p3/gitops`.

Репозиторий обязан быть публичным, потому что в конфигурации не используются
GitHub-токены или SSH-ключи. Не добавляйте секреты в Git.

## Установка

Скопируйте пример конфигурации:

```sh
cd p3
cp confs/lab.env.example confs/lab.env
```

Откройте `confs/lab.env` и установите URL своего public repository:

```sh
GIT_REPO_URL=https://github.com/USERNAME/REPOSITORY_WITH_LOGIN.git
GROUP_LOGIN=mdogadin
GIT_REPO_REVISION=main
K3D_CLUSTER_NAME=iot
K3D_VERSION=v5.8.3
ARGOCD_VERSION=v3.1.8
```

Затем запустите установку:

```sh
sudo ./scripts/install.sh
```

Скрипт:

1. устанавливает Docker, `curl`, `git`, `k3d`, `kubectl` и Argo CD CLI;
2. запускает Docker;
3. создаёт K3d-кластер `iot` с одним agent и load balancer;
4. пробрасывает порт host `8888` на HTTP-порт load balancer;
5. устанавливает Argo CD из официального manifest;
6. создаёт namespaces `argocd` и `dev`;
7. регистрирует Argo CD Application `playground`;
8. ждёт состояния `Synced Healthy` и готовности Deployment.

Поддерживаются системы с `dnf` (AlmaLinux/RHEL-подобные) и `apt-get`
(Debian/Ubuntu). В учебной AlmaLinux VM Docker устанавливается из
официального Docker CE repository.

После установки откройте новую shell-сессию или задайте kubeconfig:

```sh
export KUBECONFIG="$(k3d kubeconfig write iot)"
```

Проверка:

```sh
./scripts/check.sh
```

Ожидаемый ответ приложения:

```sh
curl http://localhost:8888/
```

Для версии `v1` ожидается JSON с `"message": "v1"`.

## Как работает GitOps

В [deployment.yaml](./gitops/deployment.yaml) указано:

```yaml
image: wil42/playground:v1
```

Argo CD Application из [шаблона](./confs/argocd-application.yaml.tpl)
наблюдает GitHub-репозиторий и путь `p3/gitops`. Его автоматическая политика
делает две вещи:

- `automated` применяет изменения из Git;
- `selfHeal` возвращает кластер к состоянию из Git, если ресурс изменили
  вручную.

Для демонстрации обновления выполните в локальной копии GitOps-репозитория:

```sh
./scripts/update-version.sh v2
git add gitops/deployment.yaml
git commit -m "Update playground to v2"
git push origin main
```

Скрипт изменяет только тег образа. После push Argo CD обнаружит новый commit:

```sh
export KUBECONFIG="$(k3d kubeconfig write iot)"
kubectl -n argocd get application playground
kubectl -n dev get deployment,pods
```

Дождитесь `Synced` и `Healthy`, затем:

```sh
curl http://localhost:8888/
```

Ответ должен содержать `"message": "v2"`. Это и есть требуемая проверка
изменения версии через GitHub.

Для ручной демонстрации состояния Argo CD можно использовать:

```sh
argocd app get playground --core
argocd app sync playground --core
```

Опция `--core` подключает CLI напрямую к Kubernetes API и не требует
отдельного ingress или пароля Argo CD.

## Проверка объектов Kubernetes

```sh
kubectl get ns
kubectl -n argocd get pods
kubectl -n argocd get application playground
kubectl -n dev get pods,deployments,services
kubectl -n dev describe deployment wil-playground
```

Должны существовать:

- namespaces `argocd` и `dev`;
- Application `playground` в namespace `argocd`;
- Deployment и Service `wil-playground` в namespace `dev`;
- один Ready pod приложения;
- image `wil42/playground:v1` или `wil42/playground:v2`.

## Диагностика

```sh
k3d cluster list
docker ps
kubectl -n argocd get pods
kubectl -n argocd describe application playground
kubectl -n dev describe pod -l app.kubernetes.io/name=wil-playground
kubectl -n argocd logs deploy/argocd-server
```

- `ImagePullBackOff`: проверьте интернет и точность image tag.
- `OutOfSync`: проверьте public repository, branch и путь `p3/gitops`.
- `Unknown` или `Connection refused`: проверьте `KUBECONFIG` и работающий
  Docker daemon.
- Argo CD не видит новый commit: убедитесь, что commit действительно pushed,
  branch совпадает с `GIT_REPO_REVISION`, а GitHub repository public.
- `curl` не подключается: проверьте, что кластер создан с
  `--port "8888:80@loadbalancer"` и порт 8888 не занят.

## Удаление

Удалить весь кластер можно без изменения системы:

```sh
k3d cluster delete iot
```

Docker, kubectl и Argo CD CLI при этом останутся установленными. Для полного
удаления Docker используйте штатный пакетный менеджер целевой ОС.

## Локальная проверка файлов

На машине без Kubernetes можно проверить синтаксис:

```sh
bash -n scripts/install.sh scripts/check.sh scripts/update-version.sh
```

Манифесты можно проверить после установки `kubectl`:

```sh
kubectl apply --dry-run=client -f gitops/
```

Полную проверку выполняет `./scripts/check.sh` внутри Linux-машины с Docker и
K3d.
