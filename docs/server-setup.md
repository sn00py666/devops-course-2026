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

## 8. Веб-сервер

- Пакет Ubuntu — `nginx`. Установка — `sudo apt update && sudo apt install -y nginx`.
- Конфигурация ресурса — `/etc/nginx/sites-available/devops-site`. В `/etc/nginx/sites-enabled/` находится одноимённая символьная ссылка. Стандартная ссылка `default` удалена, файл в `sites-available` сохранён.
- На порту `80/tcp` работает постоянное перенаправление `return 301 https://$host$request_uri;`. На `443/tcp` обслуживается `devops.local` с TLS 1.2 и 1.3. Настроены слушатели IPv4 и IPv6.
- Корень сайта — `/var/www/devops-site`. Владелец — `devops:devops`. Права каталогов — `755`, файлов — `644`. Рабочие процессы Nginx работают под `www-data` и читают содержимое сайта.
- Для сайта заданы `index index.html`, `try_files $uri $uri/ =404` и `error_page 404 /404.html`. Журналы находятся в `/var/log/nginx/devops-site.access.log` и `/var/log/nginx/devops-site.error.log`. HTTP-блок пишет перенаправления в тот же журнал доступа.
- Сертификат — `/etc/ssl/certs/devops.crt`, владелец `root:root`, права `644`. Он самоподписанный, содержит SAN `DNS:devops.local` и действует 365 дней с момента выпуска.
- Закрытый ключ — `/etc/ssl/private/devops.key`, владелец `root:root`, права `600`. Ключ хранится только в Ubuntu. Главный процесс Nginx читает его при загрузке конфигурации.

В Ubuntu сертификат и ключ создаются этими командами:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' \
  -addext 'subjectAltName=DNS:devops.local'
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Восстановите каталог сайта с помощью `sudo install -d -o devops -g devops -m 755 /var/www/devops-site`. Запишите следующую конфигурацию в `/etc/nginx/sites-available/devops-site`.

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    access_log /var/log/nginx/devops-site.access.log;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Включите ресурс и примените настройки.

```bash
sudo ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

На Mac открытый сертификат копируется через проверенное ранее SSH-соединение. Для обхода задержки разрешения имён `.local` на Mac при проверке можно явно указать адрес из раздела 2. Имя запроса и проверка SAN сохраняются:

```bash
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
curl --resolve devops.local:443:192.168.56.101 \
  --cacert ~/devops.crt -I https://devops.local/
```

Доставка выполняется из каталога `site/` командой `scripts/deploy.sh`. Команда `scripts/deploy.sh --dry-run` показывает план. Для аудита в Ubuntu используется `scripts/audit.sh`.

В снимке `04-nginx-https` сохранено состояние после настройки TLS и редиректа, до доставки страниц из репозитория.

Сценарий задаёт права символической маской `--chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r`. Это эквивалент `D755,F644`, который принимает штатный openrsync на Mac.

## 9. Контейнеризация

Docker Engine 29.10.1, клиент Docker 29.10.1 и плагин Docker Compose v5.8.0 установлены на Ubuntu ARM64 из [официального APT-репозитория Docker](https://docs.docker.com/engine/install/ubuntu/). Пакеты: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`. Ключ репозитория находится в `/etc/apt/keyrings/docker.asc`, описание источника — в `/etc/apt/sources.list.d/docker.sources`. Служба `docker` включена. В группе `docker` состоит `devops`. После добавления в группу требуется новый вход по SSH.

Проект Compose расположен в `/home/devops/app`. С Mac скопируйте каталог проекта, исключив серверный файл окружения.

```bash
rsync -avz --delete --exclude=.env --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env app/ devops:app/
```

На Ubuntu под `devops` при первом развёртывании создайте `~/app/.env` с правами `600`. Сохраняйте этот файл при повторной доставке, пока используется тот же том СУБД. Пароль генерируется локально. `.env.example` содержит шаблон, а `.gitignore` и `app/.dockerignore` исключают `.env` из репозитория и контекста сборки.

```bash
cd ~/app
if [ ! -e .env ]; then
    (
        umask 077
        printf '%s\n' POSTGRES_DB=app POSTGRES_USER=app DB_HOST=db
        printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 16)"
    ) > .env
fi
chmod 600 .env
docker compose config --quiet
docker compose up -d --build --wait
docker compose ps
```

Сервис `app` работает под непривилегированным пользователем `app` и слушает 5000 внутри контейнера. Compose публикует его только на `127.0.0.1:5000` виртуальной машины. Сервис `db` использует `postgres:16-alpine`, доступен приложению по имени `db` в сети `app_backend`. Порт 5432 не публикуется. Запуск приложения ждёт `service_healthy` для базы. Данные базы находятся в именованном томе `app_db_data`, путь в контейнере — `/var/lib/postgresql/data`.

В HTTPS-блоке `/etc/nginx/sites-available/devops-site` добавьте следующий фрагмент. Статический ресурс остаётся на `/`.

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Завершающий слеш в `proxy_pass` заменяет префикс `/app/` на `/`. Примените конфигурацию через `sudo nginx -t && sudo systemctl reload nginx`. С Mac проверьте оба ресурса:

```bash
curl --resolve devops.local:443:192.168.56.101 --cacert ~/devops.crt https://devops.local/app/health
curl --resolve devops.local:443:192.168.56.101 --cacert ~/devops.crt -I https://devops.local/
```

Для общего аудита запустите `scripts/audit.sh` в Ubuntu под `devops`. В снимке `05-docker-compose` сохранена рабочая пара контейнеров после проверки тома и до добавления прокси.
