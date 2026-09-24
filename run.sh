#!/usr/bin/env bash
# Сборка и запуск любой задачи в Docker — на хосте ничего, кроме Docker, не нужно.
#
#   ./run.sh 1_threads/task_1_rust          # собрать и запустить
#   ./run.sh 1_threads/task_1_rust 1 20     # аргументы передаются программе
#
# Контейнер удаляется после завершения (--rm).
set -euo pipefail

if [ $# -lt 1 ] || [ ! -f "$1/Dockerfile" ]; then
    echo "Использование: $0 <папка_задачи> [аргументы программы...]" >&2
    echo "Задачи с Dockerfile:" >&2
    find . -mindepth 3 -maxdepth 3 -name Dockerfile -printf '  %h\n' | sed 's|^  \./|  |' | sort >&2
    exit 1
fi

dir="${1%/}"; shift
tag="npl-$(basename "$dir" | tr '[:upper:]' '[:lower:]')"

docker build -q -t "$tag" "$dir" >/dev/null
tty=(); [ -t 0 ] && tty=(-it)   # интерактив, если запущено из терминала
docker run --rm "${tty[@]}" "$tag" "$@"
