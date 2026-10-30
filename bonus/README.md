# Bonus — локальный GitLab для Part 3

## Назначение

Bonus расширяет Part 3 локальным GitLab:

- GitLab работает внутри Kubernetes;
- используется отдельный namespace `gitlab`;
- GitLab подключён к кластеру;
- Argo CD получает GitOps-репозиторий из локального GitLab;
- приложение из Part 3 продолжает работать через `localhost:8888`.

Эта часть предполагает, что Part 3 уже полностью исправна: работают Docker,
K3d и Argo CD, а кластер называется `iot`. Bonus не заменяет обязательную
часть и не должен запускаться до успешного выполнения `p3/scripts/check.sh`.

## Архитектура

```text
K3d
├── gitlab       GitLab CE, PostgreSQL, Redis, webservice
├── argocd       Argo CD, repository Secret, Application
└── dev          wil-playground
```

GitLab устанавливается официальным Helm chart `gitlab/gitlab`. Для учебного
кластера отключены необязательные registry, Prometheus, Grafana, cert-manager
и GitLab Runner. Используется существующий Traefik K3d.

GitLab и приложение используют один внешний порт `8888`, но разные HTTP Host:

- обычный запрос `http://localhost:8888/` попадает в приложение;
- `Host: gitlab.local` попадает в GitLab.

## Установка

Убедитесь, что Part 3 уже запущена:

```sh
kubectl get nodes
k3d cluster list
kubectl -n argocd get pods
```

Подготовьте настройки:

```sh
cd bonus
cp confs/lab.env.example confs/lab.env
```

Основные параметры:

```sh
K3D_CLUSTER_NAME=iot
GITLAB_RELEASE=gitlab
GITLAB_CHART_VERSION=
GITLAB_PROJECT=inception-of-things
GITLAB_HOST_PORT=8888
ARGOCD_NAMESPACE=argocd
```

Пустой `GITLAB_CHART_VERSION` означает использование актуальной версии
официального GitLab chart. Для защиты можно заранее зафиксировать конкретную
версию после проверки совместимости с целевой системой.

Запустите:

```sh
sudo ./scripts/install.sh
```

Скрипт проверяет или устанавливает Helm, добавляет официальный Helm repository
GitLab, создаёт namespace `gitlab`, устанавливает GitLab CE и ждёт
webservice/sidekiq. Затем он получает пароль `root`, создаёт локальный проект,
загружает `p3/gitops/deployment.yaml` и `service.yaml`, создаёт repository
Secret для Argo CD и переключает Application `playground` на локальный GitLab.

Скрипт можно запускать повторно: существующий проект переиспользуется, а
GitOps-файлы обновляются.

GitLab требует заметно больше RAM, чем обычные части subject. Если Pod
остаются `Pending` или завершаются с `OOMKilled`, увеличьте память Docker/VM.

## Проверка

```sh
export KUBECONFIG="$(k3d kubeconfig write iot)"
./scripts/check.sh
```

Ручная проверка:

```sh
kubectl get ns
kubectl -n gitlab get pods
kubectl -n argocd get secret gitlab-repository
kubectl -n argocd get application playground
kubectl -n dev get pods,service
curl http://localhost:8888/
```

Ожидается состояние Argo CD `Synced Healthy`.

Открыть GitLab через curl:

```sh
curl -H 'Host: gitlab.local' http://127.0.0.1:8888/users/sign_in
```

Для браузера можно добавить в `/etc/hosts`:

```text
127.0.0.1 gitlab.local
```

Логин GitLab — `root`. Пароль хранится в Kubernetes Secret:

```sh
kubectl -n gitlab get secret gitlab-gitlab-initial-root-password \
  -o jsonpath='{.data.password}' | base64 --decode; echo
```

## GitLab и Argo CD

Внутри Kubernetes Argo CD использует DNS-адрес GitLab:

```text
http://gitlab-webservice-default.gitlab.svc:8181/root/inception-of-things.git
```

Эта ссылка и credentials записываются в Secret `argocd/gitlab-repository` с
label `argocd.argoproj.io/secret-type: repository`. Пароль не записывается в
Git. Application использует `path: gitops`, поэтому локальный проект содержит
те же manifest-файлы, что и GitHub-репозиторий Part 3.

## Проверка GitOps-обновления

Измените в локальном GitLab project файл `gitops/deployment.yaml`:

```yaml
image: wil42/playground:v1
```

на:

```yaml
image: wil42/playground:v2
```

Создайте commit в ветке `main`. Argo CD автоматически обнаружит изменение:

```sh
kubectl -n argocd get application playground
kubectl -n dev rollout status deployment/wil-playground --timeout=120s
curl http://localhost:8888/
```

Ответ должен содержать сообщение `v2`. Это подтверждает, что GitOps из Part 3
работает не только с GitHub, но и с локальным GitLab.

## Диагностика

```sh
helm -n gitlab list
kubectl -n gitlab get pods
kubectl -n gitlab get ingress
kubectl -n gitlab logs deploy/gitlab-webservice-default
kubectl -n argocd describe application playground
kubectl -n argocd get secret gitlab-repository -o yaml
```

- **GitLab `Pending`/`OOMKilled`**: увеличьте ресурсы Docker/VM.
- **Порт не проброшен**: K3d должен быть создан с
  `--port "8888:80@loadbalancer"`. Иначе пересоздайте кластер этим параметром.
- **Argo CD `RepoError`**: проверьте Secret и DNS
  `gitlab-webservice-default.gitlab.svc:8181`.
- **`OutOfSync`**: проверьте ветку `main` и путь `gitops`.
- **GitLab не открывается**: используйте Host `gitlab.local` или запись в
  `/etc/hosts`.

## Удаление

```sh
helm uninstall gitlab --namespace gitlab
kubectl delete namespace gitlab
kubectl -n argocd delete application playground
kubectl -n argocd delete secret gitlab-repository
```

Namespace `dev`, Argo CD и K3d при этом не удаляются.

## Локальная проверка

```sh
bash -n scripts/install.sh scripts/check.sh
```

На Linux с Helm можно проверить rendering:

```sh
helm template gitlab gitlab/gitlab \
  --namespace gitlab \
  --values confs/values.yaml
```
