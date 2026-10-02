#!/usr/bin/env bash
# Сборка и запуск любой задачи в Docker — на хосте ничего, кроме Docker, не нужно.
#
#   ./run.sh 1_threads/task_1_rust            # собрать и запустить
#   ./run.sh 1_threads/task_1_rust 1 20       # аргументы передаются программе
#   ./run.sh 4_client_server/task_2_ruby server
#
# Особенности по темам:
#   3_io, 5_convert   — репозиторий монтируется в контейнер, рабочая папка = папка задачи,
#                       поэтому программа видит входные файлы и пишет результаты прямо в неё
#                       (файлы создаются от имени текущего пользователя, не root).
#   4_client_server   — контейнер использует сеть хоста (--network host), так что сервер и
#                       клиенты, запущенные в разных терминалах, видят друг друга по localhost.
#
# Контейнер удаляется после завершения (--rm).
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -lt 1 ] || [ ! -f "$1/Dockerfile" ]; then
    echo "Использование: $0 <папка_задачи> [аргументы программы...]" >&2
    echo "Задачи с Dockerfile:" >&2
    find . -mindepth 3 -maxdepth 3 -name Dockerfile -printf '  %h\n' | sed 's|^  \./|  |' | sort >&2
    exit 1
fi

dir="${1%/}"; shift
tag="npl-$(basename "$dir" | tr '[:upper:]' '[:lower:]')"

echo ">>> сборка образа $tag ..." >&2
docker build -q -t "$tag" "$dir" >/dev/null

opts=(--rm)
[ -t 0 ] && opts+=(-it)               # интерактив, если запущено из терминала

case "$dir" in
    3_io/*|5_convert/*)
        opts+=(-v "$PWD:/work" -w "/work/$dir" --user "$(id -u):$(id -g)" -e HOME=/tmp) ;;
    4_client_server/*)
        opts+=(--network host) ;;
esac

docker run "${opts[@]}" "$tag" "$@"
