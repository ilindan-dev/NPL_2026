# Компилятор Zig 0.13.0 ставится из PyPI (пакет ziglang - официальная сборка Zig,
# упакованная в wheel). PyPI раздаётся через CDN, поэтому загрузка быстрая и стабильная,
# в отличие от ziglang.org, который часто отдаёт архив очень медленно.
FROM python:3.12-slim AS build
RUN pip install --no-cache-dir ziglang==0.13.0
WORKDIR /src
COPY pomodoro.zig .
RUN python -m ziglang build-exe pomodoro.zig -O ReleaseSafe

# Zig собирает статический бинарник - в итоговом образе только он
FROM debian:bookworm-slim
COPY --from=build /src/pomodoro /usr/local/bin/pomodoro
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["pomodoro"]