FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*
ARG ZIG=0.13.0
RUN arch="$(uname -m)" \
    && curl -fsSL "https://ziglang.org/download/${ZIG}/zig-linux-${arch}-${ZIG}.tar.xz" | tar -xJ -C /opt \
    && ln -s "/opt/zig-linux-${arch}-${ZIG}/zig" /usr/local/bin/zig
WORKDIR /src
COPY pomodoro.zig .
RUN zig build-exe pomodoro.zig -O ReleaseSafe

# Zig собирает статический бинарник — в итоговом образе только он
FROM debian:bookworm-slim
COPY --from=build /src/pomodoro /usr/local/bin/pomodoro
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["pomodoro"]
