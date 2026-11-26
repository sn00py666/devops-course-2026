#!/usr/bin/env bash
set -euo pipefail

remote=devops
remote_dir=/var/www/devops-site
site_url=https://devops.local/
site_ip=192.168.56.101
ca_cert="$HOME/devops.crt"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(git -C "$script_dir" rev-parse --show-toplevel)
site_dir="$repo_root/site"

rsync_args=(-avz --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r --itemize-changes)
case "$#:${1-}" in
    0:) ;;
    1:--dry-run) rsync_args+=(--dry-run) ;;
    *) printf 'Использование: %s [--dry-run]\n' "$0" >&2; exit 1 ;;
esac

if [[ ! -f "$site_dir/index.html" ]]; then
    printf 'Доставка отменена: отсутствует site/index.html.\n' >&2
    exit 1
fi
status=$(git -C "$repo_root" status --porcelain --untracked-files=normal)
if [[ -n "$status" ]]; then
    printf 'Доставка отменена: в репозитории есть незафиксированные изменения.\n' >&2
    exit 1
fi

if ! rsync "${rsync_args[@]}" -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' \
    "$site_dir/" "$remote:$remote_dir/"; then
    printf 'Синхронизация rsync завершилась ошибкой.\n' >&2
    exit 1
fi

if [[ ${1-} == --dry-run ]]; then
    printf 'Пробный запуск завершён. Файлы на сервере не изменены.\n'
    exit 0
fi
if ! curl --fail --silent --show-error --max-time 8 --noproxy devops.local \
    --resolve "devops.local:443:$site_ip" --cacert "$ca_cert" --output /dev/null "$site_url"; then
    printf 'HTTPS-проверка после доставки не пройдена.\n' >&2
    exit 1
fi
printf 'Доставлен коммит %s\n' "$(git -C "$repo_root" rev-parse --short HEAD)"
