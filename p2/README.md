# Part 2 — K3s и три приложения

## Что требуется

Эта часть запускается отдельно от `p1`. Vagrant создаёт одну VM с именем
`mdogadinS` и адресом `192.168.56.110`. В ней устанавливается K3s в режиме
server. На кластер разворачиваются три небольших HTTP-приложения на базе
`nginx:1.29-alpine`:

| Приложение | Реплики | Host в запросе |
| --- | ---: | --- |
| app1 | 1 | `app1.com` |
| app2 | 3 | `app2.com` |
| app3 | 1 | любой другой Host или без Host |

Traefik, встроенный в K3s, принимает HTTP на адресе
`192.168.56.110`. Ingress направляет запросы `app1.com` и `app2.com` в
соответствующие сервисы, а правило без `host` направляет остальные запросы в app3.
`defaultBackend` также указывает на app3; для Traefik используется явный
маршрут без ограничения Host.

## Требования к хосту

Запуск рассчитан на школьный Linux-хост с архитектурой x86_64, Vagrant и
VirtualBox. На Mac с Apple Silicon файлы можно редактировать и проверять
синтаксис, но запустить эту x86_64 VM нельзя. Нужен доступ VM в интернет для
загрузки пакетов, K3s и образа nginx.

Внутри репозитория `p1` и `p2` используют один IP-адрес. Перед запуском
убедитесь, что VM из `p1` остановлена или удалена:

```sh
cd ../p1
vagrant halt
cd ../p2
```

Не запускайте `vagrant` через `sudo`: ключи и VM должны принадлежать вашему
пользователю.

VirtualBox отображает VM с префиксом `p2-`, чтобы сохранённые VM разных
частей не конфликтовали по имени. Hostname и имена для `vagrant ssh`
остаются `mdogadinS`. Части запускаются по очереди из-за общего IP.

## Запуск

Из каталога `p2`:

```sh
./scripts/up.sh
```

Скрипт проверяет Linux x86_64, наличие Vagrant и VirtualBox, валидирует
Vagrantfile, создаёт VM, передаёт в неё `apps.yaml` по SSH и запускает
проверку. Первый запуск занимает больше времени: скачиваются box, пакеты K3s
и контейнерный образ.

Эквивалентный ручной запуск:

```sh
vagrant validate
vagrant up --provider=virtualbox
./scripts/check.sh
```

Повторное применение provisioning:

```sh
vagrant provision
./scripts/check.sh
```

Полное удаление VM (данные кластера будут потеряны):

```sh
vagrant destroy
```

## Проверка на защите: команды по eval sheet

Все команды выполняются из `p2`, если не указано «внутри VM».
Команды выполняйте по одной; после `vagrant ssh` сначала дождитесь
приглашения гостевой системы. Не вставляйте команды хоста и VM одним блоком.

### 1. Показать конфигурацию — на хосте

```sh
cat Vagrantfile
cat confs/lab.yml
cat confs/apps.yaml
vagrant validate
vagrant status
```

Показать одну VM, официальный источник AlmaLinux box, hostname `mdogadinS`
и выделенный IP `192.168.56.110`. VM должна быть `running`.
В манифесте app2 задано `replicas: 3`, а Ingress содержит правила
для `app1.com`, `app2.com` и маршрут без `host` на app3.

### 2. Войти в VM — на хосте

```sh
vagrant ssh mdogadinS
```

Дождаться `[vagrant@mdogadinS ~]$`. Пароль не нужен.
Затем выполнять по одной **внутри VM**:

```sh
hostname
ip -4 a
sudo systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl -n iot get all
kubectl -n iot get pods -o wide
kubectl -n iot get deployment app2
kubectl -n iot get deployment app2 -o jsonpath='{.spec.replicas}{"\n"}'
kubectl -n iot get ingress
kubectl -n iot describe ingress iot
```

| Что показать | Ожидаемый результат |
| --- | --- |
| `hostname` | `mdogadinS` |
| `ip -4 a` | Выделенный интерфейс с `192.168.56.110/24` |
| Сервис `k3s` | `active (running)` |
| Узлы | Один `mdogadins`, `Ready`, IP `192.168.56.110` |
| Deployment | app1 `1/1`, app2 `3/3`, app3 `1/1` |
| Pod приложений | Пять pod в `Running`, каждый `1/1` |
| Число реплик app2 | JSONPath-команда выводит `3` |
| Ingress | Класс `traefik`, app1.com → app1, app2.com → app2, остальные → app3 |

Приложения находятся в namespace `iot`, поэтому нужен флаг `-n iot`.
Объяснить, как Deployment управляет репликами, Service направляет трафик
к pod, а Ingress выбирает Service по Host запроса.

Выйти на хост:

```sh
exit
```

### 3. Проверить маршрутизацию curl — на хосте

```sh
curl -f -H 'Host: app1.com' http://192.168.56.110/
curl -f -H 'Host: app2.com' http://192.168.56.110/
curl -f -H 'Host: other.example' http://192.168.56.110/
curl -f http://192.168.56.110/
```

Ожидаемые страницы по порядку: **app1, app2, app3, app3**.
В HTML виден заголовок `<h1>app1</h1>`, `<h1>app2</h1>` или `<h1>app3</h1>`.
IP во всех запросах один, приложение выбирается по HTTP-заголовку `Host`.
`curl -f` завершится с ошибкой при HTTP 404/500.
После загрузки VM дайте K3s, Traefik и приложениям запуститься;
автоматическая проверка ниже ожидает готовности HTTP.

### 4. Открыть приложения в браузере — на хосте

Открыть файл hosts:

```sh
sudo nano /etc/hosts
```

Если соответствующей записи ещё нет, добавить строку и сохранить файл:

```text
192.168.56.110 app1.com app2.com
```

Открыть адреса с явным `http://`:

- http://app1.com/ — app1.
- http://app2.com/ — app2.
- http://192.168.56.110/ — app3.

При переходе по имени браузер сам передаёт нужный Host.
Публичный DNS для этих имён в лабораторной проверке не используется.

### 5. Автоматическая проверка — на хосте

```sh
bash scripts/check.sh
```

Проверяются SSH, IP, K3s, узел Ready, Deployment, три реплики app2
и четыре HTTP-маршрута. Ожидается завершение без ошибки со строками:

```text
HTTP Host app1.com -> app1: OK
HTTP Host app2.com -> app2: OK
HTTP Host other.example -> app3: OK
HTTP Host 192.168.56.110 -> app3: OK
Part 2: K3s, three applications, and the Host-based Ingress are ready.
```

Для показа Ingress без интерактивного входа:

```sh
vagrant ssh mdogadinS -c 'sudo /usr/local/bin/kubectl -n iot describe ingress iot'
```

### 6. Остановка и переключение на p1 — на хосте

Остановить p2:

```sh
vagrant halt
```

Повторно запустить p2:

```sh
bash scripts/up.sh
```

Либо после остановки p2 запустить p1:

```sh
cd ../p1
bash scripts/up.sh
```

## Если SSH зависает

Нажать `Ctrl+C` в зависшем терминале. На хосте из `p2` проверить:

```sh
vagrant status
vagrant ssh mdogadinS -c 'hostname'
```

Если VM `poweroff` или `saved`, запустить её:

```sh
bash scripts/up.sh
```

Если VM `running`, но вход продолжает зависать, перезапустить её:

```sh
vagrant reload
bash scripts/check.sh
```

Дождаться завершения перезапуска, затем снова выполнить `vagrant ssh mdogadinS`.
Не удалять VM ради восстановления SSH. Если перезапуск тоже завис,
посмотреть консоль VirtualBox и журнал; принудительное выключение прерывает
работу VM и требует отдельной диагностики.

## Как устроена конфигурация

### Vagrant и provisioning

`Vagrantfile` использует тот же официальный AlmaLinux box, что и `p1`, но
описывает только одну VM. Общие папки отключены, поэтому `apps.yaml`
передаётся отдельным Vagrant file provisioner в `/tmp`. Это не оставляет
зависимости от каталога репозитория внутри гостя.

`scripts/provision.sh`:

1. устанавливает `curl`, сертификаты и сетевые утилиты;
2. отключает firewalld, swap и переводит SELinux в permissive для изолированной
   учебной VM;
3. включает модули и sysctl, необходимые контейнерной сети;
4. определяет интерфейс с адресом `192.168.56.110`, не предполагая имя
   `eth1`;
5. устанавливает зафиксированную версию K3s и ждёт готовности API;
6. применяет манифесты, ждёт rollout всех Deployment и настраивает kubeconfig
   пользователя `vagrant`.

### Kubernetes-манифесты

`confs/apps.yaml` содержит namespace `iot`, три ConfigMap с HTML-страницами,
три Deployment, три ClusterIP Service и один Ingress.

ConfigMap монтируется в `index.html` контейнера nginx через `subPath`, поэтому
приложения различимы при проверке. Service скрывает pod-адреса и даёт
стабильную точку назначения для Traefik. У app2 явно указано
`spec.replicas: 3`.

Ingress использует API `networking.k8s.io/v1`, класс `traefik`, два host-based
правила, маршрут без `host` на app3 и явный `defaultBackend`. Поэтому выбор приложения выполняется
маршрутизатором, а не скриптом или отдельным прокси.

## Полезная диагностика

```sh
vagrant ssh mdogadinS -c 'sudo journalctl -u k3s -n 100 --no-pager'
vagrant ssh mdogadinS -c 'sudo /usr/local/bin/kubectl -n iot get pods -o wide'
vagrant ssh mdogadinS -c 'sudo /usr/local/bin/kubectl -n iot describe ingress iot'
vagrant ssh mdogadinS -c 'sudo /usr/local/bin/kubectl -n kube-system get pods,svc'
```

- Если VM не стартует, проверьте VT-x/AMD-V, вложенную виртуализацию и
  работоспособность kernel-модуля VirtualBox.
- Если pod имеют `Pending` или `ImagePullBackOff`, проверьте интернет внутри VM.
- Если все Host-запросы возвращают app3, проверьте точное написание заголовка
  `Host` и состояние Traefik в namespace `kube-system`.
- Для server выделено 2048 МБ RAM. Если он не становится `Ready`, сначала
  посмотрите журнал `k3s` и состояние памяти внутри VM.

## Локальная проверка файлов

На любом компьютере без запуска VM:

```sh
ruby -c Vagrantfile
bash -n scripts/provision.sh
bash -n scripts/check.sh
bash -n scripts/up.sh
```

Эти команды проверяют синтаксис. Работу Kubernetes и HTTP-маршрутизации
подтверждает только `./scripts/up.sh` на Linux x86_64.
