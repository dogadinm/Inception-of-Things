# Part 1 — K3s и Vagrant

Целевая среда: **Linux x86_64 + VirtualBox** на школьном компьютере.
На Mac с Apple Silicon можно редактировать файлы и проверять синтаксис,
но запуск этой конфигурации заблокирован: её гостевые системы — x86_64.

| Машина / hostname | Выделенный IP | K3s | CPU | RAM |
| --- | --- | --- | --- | --- |
| `mdogadinS` | `192.168.56.110/24` | server (controller) | 1 | 2048 МБ |
| `mdogadinSW` | `192.168.56.111/24` | agent (worker) | 1 | 1024 МБ |

Первый интерфейс каждой VM использует NAT для интернета и SSH Vagrant.
Второй подключён к общей host-only сети `192.168.56.0/24`.
K3s использует второй интерфейс для адресов узлов и Flannel.
Название интерфейса скрипт находит по IP, без предположений об `eth1`.

## Перед запуском в школе

1. Установить Vagrant и совместимый VirtualBox на **Linux-хосте**.
   Нужны рабочий модуль VirtualBox в ядре и аппаратная виртуализация VT-x/AMD-V.
2. По общему условию subject проект выполняется внутри виртуальной машины.
   Если Linux для проекта сам запущен как VM, включить для него **nested
   virtualization** в наружном гипервизоре: внутри него Vagrant создаёт ещё две VM.
   Если школьный компьютер не разрешает вложенную виртуализацию, потребуется
   настроить среду вместе с администратором.
3. Обеспечить доступ к интернету из хоста и обеих VM: каталог AlmaLinux,
   репозитории пакетов, `get.k3s.io`, GitHub и реестры контейнеров.
4. Убедиться, что адреса `.110` и `.111` не заняты другими лабораторными VM.
5. Проверить `confs/lab.yml`: школьный логин уже установлен в `mdogadin`.

Используются AlmaLinux **10.2**, официальный box **10.2.20261012** и K3s
**v1.36.5+k3s1**. Версии проверены 24 октября 2026 года и зафиксированы
в `confs/lab.yml`, чтобы server и agent получали одинаковый K3s.
Перед более поздней защитой проверить актуальность стабильного Linux и box.
Образ `x86_64_v2` требует процессор уровня x86-64-v2; это не ARM-образ.

Box скачивается из собственного каталога AlmaLinux на S3, явно указанного
в `config.vm.box_url`; HashiCorp registry не используется. Контрольная сумма
образа предоставляется официальным каталогом и проверяется Vagrant.

VirtualBox отображает VM с префиксом `p1-`, чтобы сохранённые VM разных
частей не конфликтовали по имени. Hostname и имена для `vagrant ssh`
остаются `mdogadinS` и `mdogadinSW`. Части запускаются по очереди из-за общего IP.

## Запуск

Если сейчас работает p2, сначала выполните в её каталоге `vagrant halt`.
Все команды запуска выполняются на хосте, вне гостевой VM.

Из корня репозитория на школьном Linux:

```sh
cd p1
bash scripts/up.sh
```

Скрипт проверяет платформу, наличие инструментов, выполняет `vagrant validate`,
запускает server, затем agent и проверяет оба узла. Первый запуск требует времени
на загрузку образа, пакетов и контейнеров.

Эквивалентные команды вручную:

```sh
vagrant validate
vagrant up --provider=virtualbox --no-parallel
./scripts/check.sh
```

При обычной работе не запускать `vagrant` через `sudo`: иначе его VM и ключи
будут принадлежать root.

## Проверка на защите: команды по eval sheet

Все команды этого раздела выполняются из `p1`, если не указано «внутри VM».
Не вставляйте команды хоста и гостя одним блоком: сначала дождитесь входа
в VM. `exit` возвращает в терминал хоста.

### 1. Показать конфигурацию и запущенные VM — на хосте

```sh
cat Vagrantfile
cat confs/lab.yml
vagrant validate
vagrant status
```

Показать две VM, официальный источник box, 1 CPU у каждой и настройки сети.
В `vagrant status` обе машины должны быть `running`. Server использует
2048 МБ RAM, worker — 1024 МБ. В subject 512–1024 МБ рекомендованы;
server увеличен до 2048 МБ после таймаутов API при локальной проверке.

### 2. Войти на server — на хосте

```sh
vagrant ssh mdogadinS
```

Дождаться приглашения `[vagrant@mdogadinS ~]$`. Пароль не нужен.
Теперь вводить следующие команды по одной **внутри server**:

```sh
hostname
ip -4 a
sudo systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl get pods -A
```

| Что показать | Ожидаемый результат |
| --- | --- |
| `hostname` | `mdogadinS` |
| `ip -4 a` | Выделенный интерфейс с `192.168.56.110/24` |
| Сервис `k3s` | `active (running)` |
| `kubectl get nodes -o wide` | Два узла `Ready`, IP `.110` и `.111` |
| Роли узлов | server — `control-plane`, worker может иметь `<none>` |

Имена узлов Kubernetes — `mdogadins` и `mdogadinsw`, в нижнем регистре.
Hostname VM сохраняют суффиксы `S` и `SW`.

Выйти из server:

```sh
exit
```

### 3. Войти на worker — на хосте

```sh
vagrant ssh mdogadinSW
```

Дождаться `[vagrant@mdogadinSW ~]$`. Затем **внутри worker**:

```sh
hostname
ip -4 a
sudo systemctl status k3s-agent --no-pager
```

Ожидаются hostname `mdogadinSW`, IP `192.168.56.111/24` и сервис
`k3s-agent` в состоянии `active (running)`. Пароль при SSH не запрашивается.
Оба узла в выводе server подтверждают, что worker присоединился к его кластеру.
Административный kubeconfig настроен на server; на worker `kubectl` для
этой проверки запускать не требуется.

```sh
exit
```

### 4. Повторить проверки без интерактивного входа — на хосте

```sh
vagrant ssh mdogadinS -c 'hostname; ip -4 a; sudo systemctl is-active k3s'
vagrant ssh mdogadinSW -c 'hostname; ip -4 a; sudo systemctl is-active k3s-agent'
vagrant ssh mdogadinS -c 'sudo /usr/local/bin/kubectl get nodes -o wide'
bash scripts/check.sh
```

Успешная автоматическая проверка заканчивается строкой:

```text
Part 1: both x86_64 nodes are Ready and accessible over SSH.
```

Нужно уметь объяснить: что делает Vagrant, отличие server от agent,
зачем нужны NAT и host-only интерфейсы, как worker использует общий токен
и почему оба узла видны через `kubectl` на server. Команды подтверждают
практические пункты eval sheet, объяснение конфигурации остаётся частью защиты.

### 5. Перейти к p2 — на хосте

```sh
vagrant halt
cd ../p2
bash scripts/up.sh
```

Обе VM p1 должны остановиться перед запуском p2: адрес `.110` общий.

## Устройство provisioning

- `Vagrantfile` создаёт обе VM и передаёт им один случайный токен через SSH.
- `scripts/provision.sh` подготавливает сеть, модули ядра, отключает swap,
  записывает `/etc/rancher/k3s/config.yaml` и устанавливает systemd-сервис K3s.
- Server запускает управляющие компоненты и SQLite; agent подключается к
  `https://192.168.56.110:6443` с тем же токеном.
- Traefik, ServiceLB и metrics-server отключены в этой части для экономии памяти.
  CoreDNS и стандартная сеть Flannel остаются включены.
- Внутри лабораторных VM firewalld отключён, SELinux переведён в permissive.
  K3s installer пока выбирает EL9 policy RPM для AlmaLinux 10, поэтому его
  установка пропускается. Настройки Linux-хоста скрипт не меняет.
- Токен хранится в `.runtime/cluster-token` с правами `0600`, исключён из Git
  и скопирован в root-only файл внутри каждой VM. Общих папок нет.
- `scripts/check.sh` проверяет SSH, архитектуру, адреса, службы, наличие ровно
  двух узлов и их состояние `Ready`.

## Остановка и повторный запуск

```sh
vagrant halt
./scripts/up.sh
```

Чтобы повторить настройку уже созданных VM:

```sh
vagrant provision mdogadinS
vagrant provision mdogadinSW
./scripts/check.sh
```

Чтобы удалить обе лабораторные VM и создать заново (их данные будут потеряны):

```sh
vagrant destroy
./scripts/up.sh
```

Не удалять `.runtime/cluster-token`, пока существуют VM: это их общий токен.
После удаления **обеих** VM можно удалить и `.runtime`, чтобы при следующем
запуске создать новый токен. На другой компьютер переносится репозиторий;
локальные `.vagrant` и `.runtime` переносить не нужно — там создаётся новый кластер.

## Если запуск не проходит

- **`VT-x/AMD-V` / `VERR_VMX_NO_VMX`**: проверить аппаратную и вложенную
  виртуализацию. ARM-хост не подходит для этого VirtualBox x86_64 lab.
- **`VERR_VMX_IN_VMX_ROOT_MODE`**: проверить конфликт VirtualBox с KVM.
  Не отключать гипервизоры школьного компьютера вслепую; сначала выяснить,
  какие VM их используют.
- **Ошибка host-only сети**: проверить существующие сети через
  `VBoxManage list hostonlyifs`, доступность `192.168.56.0/24` и отсутствие
  конфликтующих VM. Этот диапазон входит в стандартный разрешённый диапазон
  VirtualBox, если администратор не изменил настройки.
- **Server не готов / OOM**: subject советует 1 CPU и 512–1024 МБ, но текущая
  документация K3s указывает минимум 2 CPU и 2 ГБ для server. Здесь установлен
  профиль 1 CPU / 2048 МБ: при локальной проверке с 1024 МБ API отвечал
  с длительными таймаутами. При необходимости увеличить `cpus` до `2`
  в `confs/lab.yml`, затем выполнить `vagrant reload` и проверку.
- **Worker не присоединился**: проверить server, сеть и общий токен, затем
  повторить `vagrant provision mdogadinSW`.

Диагностика:

```sh
vagrant ssh mdogadinS -c 'sudo journalctl -u k3s -n 100 --no-pager'
vagrant ssh mdogadinSW -c 'sudo journalctl -u k3s-agent -n 100 --no-pager'
```

## Локальные проверки на Mac

```sh
ruby -c Vagrantfile
bash -n scripts/provision.sh
bash -n scripts/up.sh
bash -n scripts/check.sh
```

Эти команды проверяют синтаксис. Полную работоспособность подтверждает только
запуск `./scripts/up.sh` на целевом Linux x86_64 с получением двух `Ready` узлов.

## Документация

- [Официальные AlmaLinux Vagrant boxes](https://wiki.almalinux.org/installation/vagrant-boxes.html)
- [Собственный каталог AlmaLinux вне HCP](https://github.com/AlmaLinux/cloud-images/blob/main/VAGRANT_BUILD_TEST_PUBLISH.md#the-vagrant-box-catalog)
- [K3s: установка и подключение agent](https://docs.k3s.io/quick-start)
- [K3s: конфигурация](https://docs.k3s.io/installation/configuration)
- [K3s: требования и сеть](https://docs.k3s.io/installation/requirements)
