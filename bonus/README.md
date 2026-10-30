# Bonus — локальный GitLab для Argo CD

## Что показать по eval sheet

После полностью рабочей обязательной части:

1. GitLab работает локально в namespace `gitlab`.
2. Можно войти в веб-интерфейс, создать репозиторий и добавить файлы.
3. Argo CD читает GitOps-конфигурацию из локального GitLab.
4. Приложение сначала отвечает v1, после commit/push в GitLab — v2.

## Компактная архитектура

Используется официальный образ GitLab CE `gitlab/gitlab-ce:19.5.3-ce.0`,
последний стабильный релиз на 30 октября 2026. Перед более поздней защитой
проверить актуальную версию и обновить `GITLAB_IMAGE` в конфигурации.
Задание не требует Helm: на ноутбуке с 8 ГБ RAM используется один StatefulSet
вместо многокомпонентного Helm chart.

```text
K3d
├── argocd: Argo CD
├── dev: wil-playground, Service, Ingress
└── gitlab: gitlab-0, Service, Ingress, PVC, Secret, ConfigMap
```

Внутри gitlab-0 работают GitLab Rails/Puma, Sidekiq, Gitaly, PostgreSQL,
Redis и Nginx. `confs/gitlab.rb` уменьшает ресурсы: один процесс Puma,
пять потоков Sidekiq, PostgreSQL shared_buffers 128 МБ, отключены мониторинг,
registry и KAS. Для pod запрошено 1536 МБ, предел 4 ГБ RAM и 2 CPU.
Это настройки небольшой учебной установки, не гарантированный расход памяти.
Скрипт не меняет swap и ресурсы остальных приложений.

Данные, логи и конфигурация сохраняются на PVC 30 ГБ. В K3d default local-path
хранит их внутри Docker-узла: удаление всего кластера удалит и эти данные.

Порт один — 8888, Traefik выбирает приложение по Host:

- http://gitlab.local:8888/ → GitLab;
- http://localhost:8888/ → приложение из dev.

## Подготовка и запуск

Нужна рабочая p3: Docker, K3d, kubectl, curl, jq и кластер `iot`.
Helm для этого варианта не требуется. На машине должны быть свободные ресурсы
для GitLab и не менее 30 ГБ свободного диска. Остановить VM p1/p2.

Из корня проекта:

```sh
cd bonus
cp confs/lab.env.example confs/lab.env
nano confs/lab.env
export KUBECONFIG="$HOME/.kube/iot.yaml"
bash scripts/install.sh
```

Устанавливать можно от обычного пользователя с доступом к Docker и кластеру.
Первый запуск скачивает большой образ, разворачивает GitLab, настраивает базу
и может занять 10–20 минут. Скрипт переключает Argo CD только после готовности
GitLab и создания репозитория.

Пароль root и API-токен генерируются случайно и сохраняются только в Kubernetes
Secret `gitlab/gitlab-credentials`. API использует токен с ограниченным сроком,
а не HTTP Basic root/password. Репозиторий публичный внутри локального GitLab,
поэтому Argo CD читает его без администраторских credentials.

Скрипт создаёт проект `root/inception-of-things`, ветку main и каталог gitops
с тремя манифестами. При первом создании приложение получает v1.
Повторная установка добавляет недостающие файлы и сохраняет существующие
коммиты, включая версию, изменённую на защите.

## Вход в GitLab через браузер

На машине с браузером добавить запись в `/etc/hosts`, если её ещё нет:

```sh
sudo nano /etc/hosts
```

```text
127.0.0.1 gitlab.local
```

Открыть http://gitlab.local:8888/. Логин `root`. Пароль получить:

```sh
export KUBECONFIG="$HOME/.kube/iot.yaml"
kubectl -n gitlab get secret gitlab-credentials -o jsonpath='{.data.root-password}' | base64 --decode
printf '\n'
```

Пароли и токены не добавлять в Git. Если браузер на другой машине,
localhost заменить на адрес VM и настроить доступ к порту VM.

## Показ на защите: GitLab и новый репозиторий

```sh
kubectl get namespaces argocd dev gitlab
kubectl -n gitlab get statefulset,pods,services,ingress,pvc
kubectl -n gitlab exec gitlab-0 -- head -n 1 /opt/gitlab/version-manifest.txt
```

Ожидаются StatefulSet 1/1, pod gitlab-0 1/1 Running и PVC Bound.
В браузере:

1. Войти под root.
2. Открыть New project → Create blank project.
3. Создать, например, `defense-test` с README в personal namespace root.
4. Открыть README, нажать Edit, добавить строку и сделать commit.
5. Показать, что файл и commit появились в репозитории.

Отдельно открыть `root/inception-of-things`, каталог gitops и три файла:
Deployment, Service и Ingress.

## Показ на защите: локальный GitOps v1 → v2

### 1. Убедиться, что Argo CD читает GitLab

```sh
kubectl -n argocd get application playground -o jsonpath='{.spec.source.repoURL}{"\n"}{.spec.source.path}{"\n"}'
```

Ожидается:

```text
http://gitlab.gitlab.svc.cluster.local/root/inception-of-things.git
gitops
```

Внутреннее имя Service разрешается внутри Kubernetes; на хосте открывать
http://gitlab.local:8888/root/inception-of-things.

### 2. Подтвердить v1

```sh
curl -f http://localhost:8888/
bash scripts/check.sh iot v1
```

Ответ должен содержать message v1. Если предыдущая проверка оставила v2,
сначала вернуть v1 коммитом в локальном GitLab и дождаться синхронизации.

### 3. Сделать commit в GitLab

В браузере открыть `root/inception-of-things` → `gitops/deployment.yaml` → Edit.
Заменить `wil42/playground:v1` на `wil42/playground:v2`, сохранить commit
в ветку main. Файлы GitHub для этого шага не изменять.

Для варианта через git clone/commit/push можно добавить SSH-ключ в GitLab
или создать Personal Access Token с read_repository/write_repository и
использовать HTTP URL репозитория; токен вводить как пароль, не сохранять в URL.

### 4. Показать автоматическое обновление

В Argo CD открыть playground и наблюдать новый commit, Synced / Healthy.
Адрес Argo CD и получение его пароля описаны в ../p3/README.md.
В терминале:

```sh
kubectl -n argocd get application playground -w
```

После обновления Ctrl+C, затем:

```sh
kubectl -n argocd get application playground -o jsonpath='{.status.sync.revision}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
kubectl -n dev get deployment wil-playground -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -f http://localhost:8888/
bash scripts/check.sh iot v2
```

Ожидаются SHA коммита из GitLab, Synced / Healthy, тег v2 и HTTP message v2.
Автоматическая проверка дополнительно проверяет, что источник Argo CD именно
локальный GitLab, а не оставшийся от p3 GitHub.

## Остановка и диагностика

```sh
kubectl -n gitlab logs gitlab-0 --tail=80
kubectl -n gitlab describe pod gitlab-0
kubectl -n gitlab get events --sort-by=.lastTimestamp
kubectl -n argocd describe application playground
free -h
docker stats --no-stream
```

При OOMKilled, MemoryPressure или сильном торможении остановить GitLab:

```sh
kubectl -n gitlab scale statefulset gitlab --replicas=0
```

Данные останутся на PVC. Для продолжения на той же машине:

```sh
kubectl -n gitlab scale statefulset gitlab --replicas=1
kubectl -n gitlab rollout status statefulset/gitlab --timeout=1200s
```

Если памяти не хватает, повторить установку на школьной VM с большим RAM.
K3d переносится через конфигурации; Docker-узлы и PVC автоматически на другую
машину не переносятся.

## Вернуться к GitHub/p3

Сначала переключить Application обратно на URL из настроек p3, затем остановить
GitLab. Из каталога bonus:

```sh
source ../p3/confs/lab.env
sed -e "s|REPO_URL_PLACEHOLDER|$GIT_REPO_URL|g" -e "s|REVISION_PLACEHOLDER|$GIT_REPO_REVISION|g" ../p3/confs/argocd-application.yaml.tpl | kubectl apply -f -
kubectl -n argocd annotate application playground argocd.argoproj.io/refresh=hard --overwrite
```

Дождаться Synced / Healthy и ответа приложения, затем остановить GitLab.
Namespace и PVC удалять только если его данные больше не нужны.

## Официальная документация

- [GitLab в Docker](https://docs.gitlab.com/install/docker/installation/).
- [GitLab при ограниченной памяти](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/).
- [Авторизация REST API](https://docs.gitlab.com/api/rest/authentication/).
