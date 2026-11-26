# Конфигурация виртуальной машины devops-vm

Памятка для восстановления конфигурации ПР № 5 после отката на снимок `01-clean-install` перед ПР № 6. Восстанавливайте настройки по порядку. При изменении порта SSH держите открытой локальную консоль VirtualBox, чтобы сохранить доступ к Ubuntu.

## 1. Параметры машины

| Параметр | Значение |
| --- | --- |
| Виртуальная машина | `devops-vm` в Oracle VirtualBox |
| Установленная ОС | Ubuntu Server 24.04.5 LTS, ARM64 (`aarch64`) |
| Процессор | 2 виртуальных ядра |
| Память | 2048 МБ |
| Диск | 25 ГБ, динамический VDI |

На снимке `01-clean-install` уже установлены Ubuntu и OpenSSH Server, создан пользователь `student` и настроены оба сетевых интерфейса.

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Интерфейс Ubuntu | IPv4 | Назначение |
| --- | --- | --- | --- |
| 1, NAT | `enp0s8` | `10.0.2.15/24` по DHCP | Интернет и доступ к SSH через проброс порта |
| 2, Host-Only Network `HostNetwork` | `enp0s9` | `192.168.56.101/24`, статически | Прямая связь с Mac, у которого адрес `192.168.56.1/24` |

В настройках VirtualBox у обоих адаптеров включена опция «Подключить виртуальный кабель». На Mac для второго адаптера используется режим **Host-Only Network**. Маршрут по умолчанию в Ubuntu идёт через `10.0.2.2` на `enp0s8`.

В Ubuntu проверьте адреса командой `ip -brief -4 address`. Если после отката адреса на `enp0s9` нет, установите его в консоли ВМ:

```bash
sudo netplan set --origin-hint 60-host-only \
  'ethernets.enp0s9={dhcp4: false, addresses: [192.168.56.101/24]}'
sudo netplan apply
ip -brief -4 address
```

Из терминала Mac проверьте прямую связь командой `ping -c 3 192.168.56.101`.

## 3. Правило проброса портов

В VirtualBox откройте **devops-vm → Настройки → Сеть → Адаптер 1 (NAT) → Проброс портов**.

| Состояние | Имя | Протокол | IP хоста | Порт хоста | IP гостя | Порт гостя |
| --- | --- | --- | --- | --- | --- | --- |
| После отката на `01-clean-install` | `ssh` | TCP | `127.0.0.1` | `2222` | Пусто | `22` |
| После усиления защиты SSH | `ssh` | TCP | `127.0.0.1` | `2222` | Пусто | `2222` |

После отката порт гостя уже равен `22`. Измените его на `2222` в разделе 5, когда `sshd` начнёт слушать новый порт. Для подключения к адресу `192.168.56.101` через Host-Only правило NAT не используется.

## 4. Учётные записи

| Пользователь | Назначение и группы | Вход |
| --- | --- | --- |
| `student` | Исходная учётная запись установки, входит в `sudo` | Пароль в консоли ВМ. По SSH доступен на исходном снимке, до применения `AllowUsers devops`) |
| `devops` | Рабочая учётная запись, группы `devops`, `sudo`, `users` | По SSH с ключом Ed25519. Пароль пользователя используется для `sudo` |

После отката войдите в Ubuntu как `student`. Создайте учётную запись и задайте ей пароль. Поля анкеты можно оставить пустыми.

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

В терминале **Mac** скопируйте в домашний каталог `student` открытый ключ. Повторно генерировать пару ключей после отката ВМ не требуется, файлы `~/.ssh/devops_vm` и `~/.ssh/devops_vm.pub` находятся на Mac.

```bash
scp -P 2222 ~/.ssh/devops_vm.pub student@127.0.0.1:~/devops_vm.pub
```

В сеансе **Ubuntu под `student`** установите открытый ключ:

```bash
sudo install -d -m 700 -o devops -g devops /home/devops/.ssh
sudo install -m 600 -o devops -g devops "$HOME/devops_vm.pub" \
  /home/devops/.ssh/authorized_keys
rm "$HOME/devops_vm.pub"
sudo stat -c '%a %n' /home/devops/.ssh /home/devops/.ssh/authorized_keys
```

В `~/.ssh/config` на Mac уже настроен следующий блок. Если его нет, добавьте один блок:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Перед отключением входа по паролю проверьте с Mac, что `ssh devops` открывает сеанс под `devops` с ключом. Закрытый ключ остаётся на Mac.

## 5. Служба SSH

Выполните в **консоли Ubuntu**. Основной файл `/etc/ssh/sshd_config` подключает файлы из `/etc/ssh/sshd_config.d/`. Сохраните его резервную копию и создайте файл с параметрами ПР № 5:

```bash
sudo cp -n /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'CONFIG'
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
CONFIG

sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries|allowusers) '
```

Ожидаемые значения: `port 2222`, `permitrootlogin no`, `passwordauthentication no`, `pubkeyauthentication yes`, `maxauthtries 3`, `allowusers devops`. Если вывод отличается, проверьте, нет ли активной директивы с другим значением в файле, который читается раньше. Строки с `#` являются комментариями. Продолжайте после успешной проверки синтаксиса и значений.

На Ubuntu 24.04 переключите SSH с активации через сокет на службу и проверьте порт:

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
sudo ss -ltnp | grep sshd
```

После появления слушателей `0.0.0.0:2222` и `[::]:2222` измените **порт гостя на 2222** в правиле NAT из раздела 3. С Mac в новом терминале подтвердите вход командой `ssh devops`. В консоли ВМ оставьте возможность вернуться к настройкам, пока повторный вход не проверен.

## 6. Правила межсетевого экрана

При восстановлении из **консоли Ubuntu** задайте политики и правила до включения UFW:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw logging medium
sudo ufw enable
sudo ufw status verbose
```

В итоговом состоянии UFW активен. Входящий трафик по умолчанию запрещён, исходящий разрешён. Порт SSH `2222/tcp` имеет правило `LIMIT`, а `80/tcp` и `443/tcp` имеют правила `ALLOW`. При включённом IPv6 UFW выводит также соответствующие правила `(v6)`. После включения проверьте вход из нового терминала Mac командой `ssh devops`.

Для проверки блокировки выполните на Mac `curl -m 3 http://192.168.56.101:8080`. Запрос должен завершиться по тайм-ауту. В Ubuntu запись видна в журнале ядра:

```bash
sudo journalctl -k --since '5 min ago' --no-pager | grep -F '[UFW BLOCK]' | tail -5
```

В записи этой проверки `SRC=192.168.56.1`, `DST=192.168.56.101`, `PROTO=TCP`, `DPT=8080`.

## 7. Снимки состояния

| Снимок | Когда создан |
| --- | --- |
| `01-clean-install` | После установки Ubuntu, настройки двух интерфейсов и проверки первоначального SSH под `student` |
| `02-keys-configured` | После создания `devops`, установки открытого ключа и успешного входа командой `ssh devops` |
| `03-ssh-hardened` | После переноса SSH на порт 2222, запрета входа root и по паролю и проверки доступа по ключу. Правила UFW и полное локальное имя настроены следующим этапом |

Для проверки ПР № 6 используется `01-clean-install`. После отката повторите разделы 4–6, затем настройте локальные имена и проверьте новый вход и статус UFW. Существующие снимки для этого переименовывать или перезаписывать не требуется.

## Локальные имена и проверка с Mac

В `/etc/hosts` **на Mac** должна быть строка `192.168.56.101 devops.local`. Откат гостевой системы эту запись не затрагивает. Если её нет, добавьте через `sudo nano /etc/hosts`.

В **Ubuntu** задайте короткое имя и в `/etc/hosts` замените строку для `127.0.1.1` на `127.0.1.1 devops-vm.devops.local devops-vm`. Если соответствующей строки нет, добавьте её через `sudo nano /etc/hosts`.

```bash
sudo hostnamectl set-hostname devops-vm
hostname -f
```

После правки `/etc/hosts` команда `hostname -f` должна вывести `devops-vm.devops.local`. Из терминала **Mac** проверьте имя и вход по ключу через Host-Only:

```bash
ping -c 3 devops.local
ssh -o IdentitiesOnly=yes -i ~/.ssh/devops_vm -p 2222 devops@devops.local 'whoami; hostname -f'
```

Ожидаемый вывод SSH: `devops` и `devops-vm.devops.local`.
