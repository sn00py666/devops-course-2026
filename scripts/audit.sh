#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

passed=0
failed=0
cert_min_days=${CERT_MIN_DAYS:-30}
if [[ ! "$cert_min_days" =~ ^(0|[1-9][0-9]{0,4})$ ]]; then
    printf 'CERT_MIN_DAYS должен содержать целое число от 0 до 99999.\n' >&2
    exit 1
fi

check() {
    local label=$1 expected=$2 actual=$3
    if [[ "$actual" == "$expected" ]]; then
        printf '[OK]   %s\n' "$label"
        passed=$((passed + 1))
    else
        printf '[FAIL] %s (ожидалось %s, получено %s)\n' "$label" "$expected" "${actual:-<нет>}"
        failed=$((failed + 1))
    fi
}

sudo -v
ssh_config=$(sudo -n sshd -T)
ufw_status=$(sudo -n ufw status verbose)
printf 'Аудит конфигурации %s\n\n[1] SSH\n' "$(hostname -f)"
check 'Вход root запрещён' no "$(awk '$1=="permitrootlogin" {print $2}' <<< "$ssh_config")"
check 'Вход по паролю запрещён' no "$(awk '$1=="passwordauthentication" {print $2}' <<< "$ssh_config")"
check 'Порт SSH отличается от 22' yes "$(awk '$1=="port" && $2!=22 {ok=1} $1=="port" && $2==22 {standard=1} END {print (ok && !standard ? "yes" : "no")}' <<< "$ssh_config")"
check 'MaxAuthTries равен 3' 3 "$(awk '$1=="maxauthtries" {print $2}' <<< "$ssh_config")"

printf '\n[2] Межсетевой экран\n'
check 'UFW активен' active "$(awk '$1=="Status:" {print $2}' <<< "$ufw_status")"
check 'Политика для входящих соединений' deny "$(awk '$1=="Default:" {print $2}' <<< "$ufw_status")"

printf '\n[3] Учётные записи\n'
awk -F: '$3>=1000 && $3<65534 {printf "%s (uid=%s)\n", $1, $3}' /etc/passwd

printf '\n[4] Веб-сервер\n'
state=$(systemctl is-active nginx || true)
check 'Nginx активен' active "$state"
nginx_valid=no
if sudo -n nginx -t >/dev/null 2>&1; then nginx_valid=yes; fi
check 'Синтаксис конфигурации Nginx' yes "$nginx_valid"

cert_valid=no
if openssl x509 -in /etc/ssl/certs/devops.crt -noout \
    -checkend "$((cert_min_days * 86400))" >/dev/null 2>&1; then cert_valid=yes; fi
check "Сертификат действителен ещё не менее $cert_min_days дн." yes "$cert_valid"

writable=$(sudo -n find /var/www/devops-site -perm -o+w -print)
key_mode=$(sudo -n stat -c '%a' /etc/ssl/private/devops.key)
check 'В ресурсе отсутствуют объекты с записью для всех, права ключа 600' '600:' "$key_mode:$writable"

printf '\n[5] Контейнеризация\n'
docker_state=$(systemctl is-active docker || true)
check 'Docker активен' active "$docker_state"
db_health=$(docker inspect --format '{{.State.Health.Status}}' app-db-1 2>/dev/null || true)
check 'PostgreSQL в состоянии healthy' healthy "$db_health"

socket_state=unavailable
if tcp_listeners=$(ss -H -tln); then
    socket_state=$(awk '
        $4 ~ /:5000$/ {
            if ($4 == "127.0.0.1:5000") loopback=1
            else external=1
        }
        $4 ~ /:5432$/ { database=1 }
        END { print (loopback && !external && !database ? "yes" : "no") }
    ' <<< "$tcp_listeners")
fi
check 'Порт 5000 привязан к loopback, порт 5432 не опубликован' yes "$socket_state"

audit_user=${SUDO_USER:-$(id -un)}
env_owner_home=$(getent passwd "$audit_user" | cut -d: -f6)
env_mode=$(stat -c '%a' "$env_owner_home/app/.env" 2>/dev/null || true)
check 'Права файла ~/app/.env равны 600' 600 "$env_mode"

printf '\nПройдено: %d, не пройдено: %d\n' "$passed" "$failed"
((failed == 0))
